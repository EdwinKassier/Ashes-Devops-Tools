/**
 * Copyright 2026 Ashes
 *
 * App Services Stage - the application golden path.
 *
 * A service team adds one entry to var.services and gets, in the environment host
 * project: an Artifact Registry docker repo, a least-privilege runtime SA, a Cloud
 * Run v2 service (internal ingress, Direct VPC egress, scale-to-zero, secrets from
 * Secret Manager), an optional private-IP Cloud SQL Postgres with IAM auth, and an
 * optional GitHub deploy identity (WIF, bound on the immutable repository_id),
 * per-service Cloud Monitoring alert policies (5xx ratio, p99 latency) and an
 * optional Pub/Sub topic + subscription + dead-letter topic.
 * An optional GKE Autopilot cluster is available at environment level.
 * Everything is behind flags: the default (services = {}) creates nothing.
 */

locals {
  services_with_db     = { for k, s in var.services : k => s if s.database != null }
  services_with_github = { for k, s in var.services : k => s if s.github != null }
  services_with_alerts = var.enable_alerts ? { for k, s in var.services : k => s if s.alerts.enabled } : {}
  services_with_pubsub = { for k, s in var.services : k => s if s.pubsub.enabled }

  # Deterministic Pub/Sub names (env vars + outputs without read-back).
  pubsub_topic        = { for k, s in local.services_with_pubsub : k => "projects/${var.project_id}/topics/${k}" }
  pubsub_subscription = { for k, s in local.services_with_pubsub : k => "projects/${var.project_id}/subscriptions/${k}-sub" }
  pubsub_dlq_topic    = { for k, s in local.services_with_pubsub : k => "projects/${var.project_id}/topics/${k}-dlq" }
  pubsub_agent        = var.project_number == null ? null : "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  # Deterministic names (known at plan time; no read-back of computed attributes).
  runtime_sa_email = { for k, s in var.services : k => "${k}-run@${var.project_id}.iam.gserviceaccount.com" }
  deploy_sa_email  = { for k, s in local.services_with_github : k => "${k}-deploy@${var.project_id}.iam.gserviceaccount.com" }
  db_instance_name = { for k, s in local.services_with_db : k => "${k}-db" }

  image_repository = { for k, s in var.services : k => "${var.region}-docker.pkg.dev/${var.project_id}/${k}/${k}" }

  # The image the first revision runs: the service's own, else the placeholder.
  initial_image = { for k, s in var.services : k => coalesce(s.image, var.bootstrap_image) }

  # Flatten secret refs into one IAM grant per (service, secret).
  secret_grants = merge([
    for k, s in var.services : {
      for env_name, ref in s.secrets : "${k}/${env_name}" => { service = k, secret = ref.secret }
    }
  ]...)

  runtime_role_grants = merge([
    for k, s in var.services : {
      for role in s.runtime_project_roles : "${k}/${role}" => { service = k, role = role }
    }
  ]...)

  invoker_grants = merge([
    for k, s in var.services : {
      for m in s.invoker_members : "${k}/${m}" => { service = k, member = m }
    }
  ]...)

  # ---------------------------------------------------------------------------
  # App-deploy Workload Identity Federation
  # ---------------------------------------------------------------------------
  wif_pool_id   = coalesce(var.app_deploy_wif_pool_id, substr("apps-${var.environment}", 0, 32))
  wif_pool_name = var.enable_app_deploy_wif ? "projects/${var.project_number}/locations/global/workloadIdentityPools/${local.wif_pool_id}" : null
  # The provider exists only once a service declares a deploy identity, so its
  # attribute_condition is never an empty (always-false) expression.
  create_wif_provider    = var.enable_app_deploy_wif && length(local.services_with_github) > 0
  wif_provider_name      = local.create_wif_provider ? "${local.wif_pool_name}/providers/github" : null
  github_oidc_issuer_uri = "https://token.actions.githubusercontent.com"
  wif_provider_cel_owner = var.github_repository_owner_id == null ? "" : "assertion.repository_owner_id == \"${var.github_repository_owner_id}\" && "
  wif_provider_cel_clause = distinct([
    for k, s in local.services_with_github : join(" && ", compact([
      "assertion.repository_id == \"${s.github.repository_id}\"",
      s.github.ref == null ? "" : "assertion.ref == \"${s.github.ref}\"",
      s.github.environment == null ? "" : "(has(assertion.environment) && assertion.environment == \"${s.github.environment}\")",
    ]))
  ])
  # Fail closed: a token is accepted only if it matches a declared service's
  # (repository_id [, ref] [, environment]) tuple — never on mutable names.
  wif_provider_cel_any    = join(" || ", [for c in local.wif_provider_cel_clause : "(${c})"])
  wif_attribute_condition = "${local.wif_provider_cel_owner}${length(local.wif_provider_cel_clause) > 1 ? "(${local.wif_provider_cel_any})" : local.wif_provider_cel_any}"

  # ---------------------------------------------------------------------------
  # APIs
  # ---------------------------------------------------------------------------
  required_apis = !var.enable_project_services ? [] : distinct(concat(
    length(var.services) > 0 ? ["run.googleapis.com", "artifactregistry.googleapis.com", "iam.googleapis.com"] : [],
    length(var.services) > 0 && var.enable_vulnerability_scanning ? ["containerscanning.googleapis.com"] : [],
    length(var.services) > 0 && var.enable_on_demand_scanning ? ["ondemandscanning.googleapis.com"] : [],
    length(local.secret_grants) > 0 ? ["secretmanager.googleapis.com"] : [],
    length(local.services_with_db) > 0 ? ["sqladmin.googleapis.com", "servicenetworking.googleapis.com"] : [],
    var.enable_app_deploy_wif ? ["iam.googleapis.com", "iamcredentials.googleapis.com", "sts.googleapis.com"] : [],
    var.enable_gke_autopilot ? ["container.googleapis.com"] : [],
    length(local.services_with_alerts) > 0 ? ["monitoring.googleapis.com"] : [],
    length(local.services_with_pubsub) > 0 ? ["pubsub.googleapis.com"] : [],
  ))
}

resource "google_project_service" "this" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# =============================================================================
# ARTIFACT REGISTRY — one docker repo per service
# =============================================================================

module "registry" {
  source   = "../../artifact-registry"
  for_each = var.services

  project_id   = var.project_id
  region       = var.region
  kms_key_name = var.artifact_registry_kms_key_name
  labels       = merge(var.labels, { service = each.key })

  # Scan pushed images; the stage enables containerscanning.googleapis.com
  # itself (required_apis), so the module does not manage the API.
  enable_vulnerability_scanning = var.enable_vulnerability_scanning
  enable_container_scanning_api = false

  repositories = {
    (each.key) = {
      description            = "Container images for the ${each.key} service (${var.environment})."
      format                 = "DOCKER"
      immutable_tags         = each.value.artifact_registry.immutable_tags
      cleanup_policy_dry_run = each.value.artifact_registry.cleanup_policy_dry_run
      cleanup_policies = {
        "keep-most-recent" = {
          action               = "KEEP"
          most_recent_versions = { keep_count = each.value.artifact_registry.keep_count }
        }
        "delete-untagged" = {
          action    = "DELETE"
          condition = { tag_state = "UNTAGGED", older_than = each.value.artifact_registry.delete_untagged_older_than }
        }
      }
    }
  }

  depends_on = [google_project_service.this]
}

# =============================================================================
# RUNTIME IDENTITY — least privilege: no project roles unless asked for
# =============================================================================
#
# Why raw google_service_account here rather than modules/gcp/iam/service-account
# (and raw WIF pool/provider below rather than modules/gcp/iam/workload-identity):
# these are for_each over the caller's var.services keys. Wrapping them in a
# module changes every address (google_service_account.runtime["api"] ->
# module.runtime_sa["api"]...), and a `moved` block cannot express per-key moves
# for keys only known from tfvars — a whole-resource `moved` into a for_each
# module is silently ignored and plans destroy + create. Recreating an SA gives
# it a new unique_id and drops every binding on it, so that refactor would break
# live environments. The workload-identity module also differs in behaviour
# (name-based `sub` condition, extra attribute mappings). Keep these inline.

resource "google_service_account" "runtime" {
  for_each = var.services

  project      = var.project_id
  account_id   = "${each.key}-run"
  display_name = "${each.key} runtime (${var.environment})"
  description  = "Cloud Run runtime identity for ${each.key}. Grants: secretAccessor on its own secrets, Cloud SQL client/instanceUser on its own instance."

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_iam_member" "runtime" {
  for_each = local.secret_grants

  project   = var.project_id
  secret_id = each.value.secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runtime_sa_email[each.value.service]}"

  depends_on = [google_service_account.runtime]
}

resource "google_project_iam_member" "runtime_extra" {
  for_each = local.runtime_role_grants

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${local.runtime_sa_email[each.value.service]}"

  depends_on = [google_service_account.runtime]
}

# =============================================================================
# CLOUD RUN
# =============================================================================

module "service" {
  source   = "../../compute/cloud-run"
  for_each = var.services

  project_id            = var.project_id
  location              = var.region
  name                  = each.key
  image                 = local.initial_image[each.key]
  service_account_email = local.runtime_sa_email[each.key]

  ingress                = each.value.ingress
  enable_unauthenticated = each.value.enable_unauthenticated

  cpu                = each.value.cpu
  memory             = each.value.memory
  min_instance_count = each.value.min_instances
  max_instance_count = each.value.max_instances
  concurrency        = each.value.concurrency
  timeout            = each.value.timeout

  env_vars = merge(
    each.value.env_vars,
    each.value.database == null ? {} : {
      DB_INSTANCE_CONNECTION_NAME = "${var.project_id}:${var.region}:${local.db_instance_name[each.key]}"
      DB_IAM_USER                 = trimsuffix(local.runtime_sa_email[each.key], ".gserviceaccount.com")
      DB_NAME                     = try(each.value.database.databases[0], "")
    },
    each.value.pubsub.enabled ? {
      PUBSUB_TOPIC        = local.pubsub_topic[each.key]
      PUBSUB_SUBSCRIPTION = local.pubsub_subscription[each.key]
    } : {}
  )
  secret_env_vars = [for name, ref in each.value.secrets : { name = name, secret = ref.secret, version = ref.version }]

  # Direct VPC egress into the environment Shared VPC subnet (no connector).
  vpc_access = {
    egress = each.value.vpc_egress
    network_interfaces = {
      network    = var.network_id
      subnetwork = coalesce(each.value.subnetwork_id, var.subnetwork_id)
    }
  }

  binary_authorization = each.value.enable_binary_authorization ? { policy = each.value.binary_authorization_policy } : null

  enable_deletion_protection = coalesce(each.value.enable_deletion_protection, var.enable_deletion_protection)
  labels                     = merge(var.labels, { service = each.key }, each.value.labels)

  # Secret IAM must exist before the first revision resolves its secret refs.
  depends_on = [
    google_service_account.runtime,
    google_secret_manager_secret_iam_member.runtime,
    google_project_service.this,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = local.invoker_grants

  project  = var.project_id
  location = var.region
  name     = module.service[each.value.service].name
  role     = "roles/run.invoker"
  member   = each.value.member
}

# =============================================================================
# CLOUD SQL (optional per service) — private IP via the host VPC's PSA
# =============================================================================

module "database" {
  source   = "../../data/cloud-sql"
  for_each = local.services_with_db

  project_id       = var.project_id
  region           = var.region
  name             = local.db_instance_name[each.key]
  database_version = each.value.database.database_version
  edition          = each.value.database.edition
  tier             = each.value.database.tier

  # Private Service Access on the env VPC is created by the host stage
  # (enable_private_service_access defaults to true); the caller orders this
  # module after it (depends_on = [module.host] in envs/gcp/workload).
  private_network = var.network_id

  enable_iam_authentication     = true
  enable_high_availability      = each.value.database.enable_high_availability
  enable_point_in_time_recovery = each.value.database.enable_point_in_time_recovery
  encryption_key_name           = each.value.database.encryption_key_name
  enable_deletion_protection    = coalesce(each.value.database.enable_deletion_protection, var.enable_deletion_protection)

  databases = each.value.database.databases

  # The runtime SA is the (only) application database user — IAM auth, no password.
  users = [{
    name = trimsuffix(local.runtime_sa_email[each.key], ".gserviceaccount.com")
    type = "CLOUD_IAM_SERVICE_ACCOUNT"
  }]

  labels = merge(var.labels, { service = each.key })

  depends_on = [google_project_service.this, google_service_account.runtime]
}

# Cloud SQL has no instance-level IAM, so the project grant is narrowed to this
# service's instance with an IAM condition.
resource "google_project_iam_member" "runtime_sql" {
  for_each = merge([
    for k, s in local.services_with_db : {
      "${k}/client"       = { service = k, role = "roles/cloudsql.client" }
      "${k}/instanceUser" = { service = k, role = "roles/cloudsql.instanceUser" }
    }
  ]...)

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${local.runtime_sa_email[each.value.service]}"

  condition {
    title       = "${each.value.service}-db-only"
    description = "Only the ${local.db_instance_name[each.value.service]} instance."
    expression  = "resource.name == \"projects/${var.project_id}/instances/${local.db_instance_name[each.value.service]}\""
  }

  depends_on = [google_service_account.runtime]
}

# =============================================================================
# DEPLOY IDENTITY — GitHub Actions via an app-only WIF pool in the host project
# =============================================================================

resource "google_iam_workload_identity_pool" "apps" {
  count = var.enable_app_deploy_wif ? 1 : 0

  project                   = var.project_id
  workload_identity_pool_id = local.wif_pool_id
  display_name              = substr("App deploys (${var.environment})", 0, 32)
  description               = "GitHub Actions identities that deploy application services in ${var.environment}. Separate from the infrastructure (gcp-bootstrap) pool."

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  # CKV_GCP_125 only accepts an `assertion.sub == "repo:owner/name:..."` condition,
  # i.e. a MUTABLE repo name. This provider deliberately keys on the immutable
  # numeric repository_id (plus optional ref/environment/owner_id), fail-closed to
  # the declared services, and bindings are per-repository_id principalSets.
  # checkov:skip=CKV_GCP_125:Condition pins immutable assertion.repository_id per declared service (stronger than a name-based sub match).
  count = local.create_wif_provider ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.apps[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.repository"          = "assertion.repository"
    "attribute.ref"                 = "assertion.ref"
  }

  attribute_condition = local.wif_attribute_condition

  oidc {
    issuer_uri = local.github_oidc_issuer_uri
  }
}

resource "google_service_account" "deploy" {
  for_each = local.services_with_github

  project      = var.project_id
  account_id   = "${each.key}-deploy"
  display_name = "${each.key} deploy (${var.environment})"
  description  = "GitHub Actions deploy identity for ${each.key} (repository_id ${each.value.github.repository_id}). run.developer on the service, artifactregistry.writer on the repo, serviceAccountUser on the runtime SA only."

  depends_on = [google_project_service.this]
}

# Only tokens from this repository (by immutable numeric ID) may impersonate.
resource "google_service_account_iam_member" "deploy_wif" {
  for_each = local.services_with_github

  service_account_id = google_service_account.deploy[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repository_id/${each.value.github.repository_id}"

  depends_on = [google_iam_workload_identity_pool_provider.github]
}

resource "google_cloud_run_v2_service_iam_member" "deploy" {
  for_each = local.services_with_github

  project  = var.project_id
  location = var.region
  name     = module.service[each.key].name
  role     = "roles/run.developer"
  member   = "serviceAccount:${local.deploy_sa_email[each.key]}"

  depends_on = [google_service_account.deploy]
}

resource "google_artifact_registry_repository_iam_member" "deploy" {
  for_each = local.services_with_github

  project    = var.project_id
  location   = var.region
  repository = module.registry[each.key].repository_ids[each.key]
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${local.deploy_sa_email[each.key]}"

  depends_on = [google_service_account.deploy]
}

# actAs on the runtime SA only (needed to roll a new revision), never project-wide.
resource "google_service_account_iam_member" "deploy_act_as_runtime" {
  for_each = local.services_with_github

  service_account_id = google_service_account.runtime[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.deploy_sa_email[each.key]}"

  depends_on = [google_service_account.deploy]
}

# =============================================================================
# ALERT POLICIES — per service, on its Cloud Run revisions
# =============================================================================
#
# Native resources rather than modules/gcp/monitoring/alert-policy: that module
# builds project-wide policies (every Cloud Run service in one condition) with
# rate-based thresholds; the golden path needs one policy per service, filtered
# on its service_name, with a 5xx RATIO.

resource "google_monitoring_alert_policy" "error_ratio" {
  for_each = local.services_with_alerts

  project      = var.project_id
  display_name = "${var.environment}/${each.key}: 5xx ratio > ${format("%.3g", each.value.alerts.error_ratio_threshold * 100)}%"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "${each.key} 5xx / all requests"
    condition_threshold {
      filter             = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${each.key}\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\""
      denominator_filter = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${each.key}\" AND metric.type = \"run.googleapis.com/request_count\""
      comparison         = "COMPARISON_GT"
      threshold_value    = each.value.alerts.error_ratio_threshold
      duration           = each.value.alerts.duration

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.labels.service_name"]
      }
      denominator_aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.labels.service_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.alert_notification_channel_ids

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "More than ${format("%.3g", each.value.alerts.error_ratio_threshold * 100)}% of requests to Cloud Run service ${each.key} (${var.environment}) returned 5xx for ${each.value.alerts.duration}. Check the latest revision's logs and roll back if it was a deploy."
    mime_type = "text/markdown"
  }

  user_labels = merge(var.labels, { service = each.key })

  depends_on = [google_project_service.this]
}

resource "google_monitoring_alert_policy" "latency_p99" {
  for_each = local.services_with_alerts

  project      = var.project_id
  display_name = "${var.environment}/${each.key}: p99 latency > ${each.value.alerts.p99_latency_ms}ms"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "${each.key} p99 request latency"
    condition_threshold {
      filter          = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${each.key}\" AND metric.type = \"run.googleapis.com/request_latencies\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.alerts.p99_latency_ms
      duration        = each.value.alerts.duration

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_PERCENTILE_99"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = ["resource.labels.service_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.alert_notification_channel_ids

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "p99 request latency of Cloud Run service ${each.key} (${var.environment}) has exceeded ${each.value.alerts.p99_latency_ms}ms for ${each.value.alerts.duration}."
    mime_type = "text/markdown"
  }

  user_labels = merge(var.labels, { service = each.key })

  depends_on = [google_project_service.this]
}

# =============================================================================
# PUB/SUB — optional per service: topic, subscription, dead-letter topic
# =============================================================================

resource "google_pubsub_topic" "service" {
  for_each = local.services_with_pubsub

  project      = var.project_id
  name         = each.key
  kms_key_name = var.pubsub_kms_key_name
  labels       = merge(var.labels, { service = each.key })

  depends_on = [google_project_service.this]
}

resource "google_pubsub_topic" "dead_letter" {
  for_each = local.services_with_pubsub

  project      = var.project_id
  name         = "${each.key}-dlq"
  kms_key_name = var.pubsub_kms_key_name
  labels       = merge(var.labels, { service = each.key })

  depends_on = [google_project_service.this]
}

resource "google_pubsub_subscription" "service" {
  for_each = local.services_with_pubsub

  project                    = var.project_id
  name                       = "${each.key}-sub"
  topic                      = google_pubsub_topic.service[each.key].id
  ack_deadline_seconds       = each.value.pubsub.ack_deadline_seconds
  message_retention_duration = each.value.pubsub.message_retention_duration

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter[each.key].id
    max_delivery_attempts = each.value.pubsub.max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Never expire for inactivity (the default deletes an idle subscription after 31 days).
  expiration_policy {
    ttl = ""
  }

  labels = merge(var.labels, { service = each.key })
}

# Messages on a topic with no subscription are dropped: this keeps dead letters.
resource "google_pubsub_subscription" "dead_letter" {
  for_each = local.services_with_pubsub

  project                    = var.project_id
  name                       = "${each.key}-dlq-sub"
  topic                      = google_pubsub_topic.dead_letter[each.key].id
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"

  expiration_policy {
    ttl = ""
  }

  labels = merge(var.labels, { service = each.key })
}

# Runtime SA: publish to ITS topic, consume ITS subscription. Nothing project-wide.
resource "google_pubsub_topic_iam_member" "runtime_publisher" {
  for_each = local.services_with_pubsub

  project = var.project_id
  topic   = google_pubsub_topic.service[each.key].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.runtime_sa_email[each.key]}"

  depends_on = [google_service_account.runtime]
}

resource "google_pubsub_subscription_iam_member" "runtime_subscriber" {
  for_each = local.services_with_pubsub

  project      = var.project_id
  subscription = google_pubsub_subscription.service[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.runtime_sa_email[each.key]}"

  depends_on = [google_service_account.runtime]
}

# Dead-letter forwarding: the Pub/Sub service agent must publish to the DLQ
# topic and acknowledge (subscribe) on the source subscription.
resource "google_pubsub_topic_iam_member" "agent_dead_letter_publisher" {
  for_each = local.services_with_pubsub

  project = var.project_id
  topic   = google_pubsub_topic.dead_letter[each.key].name
  role    = "roles/pubsub.publisher"
  member  = local.pubsub_agent
}

resource "google_pubsub_subscription_iam_member" "agent_source_subscriber" {
  for_each = local.services_with_pubsub

  project      = var.project_id
  subscription = google_pubsub_subscription.service[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_agent
}

# =============================================================================
# GKE AUTOPILOT (optional, env level)
# =============================================================================

module "gke" {
  source = "../../compute/gke-autopilot"
  count  = var.enable_gke_autopilot ? 1 : 0

  project_id = var.project_id
  name       = coalesce(var.gke_cluster_name, "${var.environment}-apps")
  location   = var.region
  network    = var.network_id
  subnetwork = var.subnetwork_id

  cluster_secondary_range_name  = var.gke_cluster_secondary_range_name
  services_secondary_range_name = var.gke_services_secondary_range_name
  master_ipv4_cidr_block        = var.gke_master_ipv4_cidr_block
  master_authorized_networks    = var.gke_master_authorized_networks

  enable_deletion_protection = var.enable_deletion_protection
  resource_labels            = var.labels

  depends_on = [google_project_service.this]
}
