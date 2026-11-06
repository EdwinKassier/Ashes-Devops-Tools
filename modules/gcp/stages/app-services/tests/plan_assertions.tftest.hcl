# Plan assertions for the app-services stage (the application golden path).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id     = "acme-dev-host-abcd"
  project_number = "222222222222"
  region         = "europe-west1"
  environment    = "dev"
  network_id     = "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
  subnetwork_id  = "projects/acme-dev-host-abcd/regions/europe-west1/subnetworks/acme-dev-vpc-private-europe-west1-b"

  github_repository_owner_id = "42"
}

# The default (services = {}, every flag off) must create nothing at all.
run "default_creates_nothing" {
  command = plan

  assert {
    condition = (
      length(module.registry) == 0 &&
      length(google_service_account.runtime) == 0 &&
      length(module.service) == 0 &&
      length(module.database) == 0 &&
      length(google_service_account.deploy) == 0 &&
      length(google_iam_workload_identity_pool.apps) == 0 &&
      length(google_iam_workload_identity_pool_provider.github) == 0 &&
      length(module.gke) == 0 &&
      length(google_project_service.this) == 0
    )
    error_message = "with services = {} and every flag off, the stage must create nothing."
  }

  assert {
    condition     = output.workload_identity_provider == null && length(output.services) == 0
    error_message = "outputs must be empty/null by default."
  }
}

# One service with a deploy identity: repo + runtime SA + Cloud Run + deploy SA.
run "one_service_full_golden_path" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services = {
      api = {
        secrets = { API_KEY = { secret = "api-key" } }
        github  = { repository_id = "123456789", repository = "acme/api" }
      }
    }
  }

  assert {
    condition     = length(module.registry) == 1 && length(google_service_account.runtime) == 1 && length(module.service) == 1 && length(google_service_account.deploy) == 1
    error_message = "one service must create exactly one repo, runtime SA, Cloud Run service and deploy SA."
  }

  assert {
    condition     = length(module.database) == 0
    error_message = "no database may be created unless the service declares one."
  }

  assert {
    condition     = google_service_account.runtime["api"].account_id == "api-run" && google_service_account.deploy["api"].account_id == "api-deploy"
    error_message = "runtime/deploy SA IDs must be <service>-run / <service>-deploy."
  }

  # Ingress is internal by default, and Direct VPC egress lands on the env subnet.
  assert {
    condition     = module.service["api"].ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY"
    error_message = "Cloud Run ingress must default to INGRESS_TRAFFIC_INTERNAL_ONLY."
  }

  assert {
    condition     = output.services["api"].image_repository == "europe-west1-docker.pkg.dev/acme-dev-host-abcd/api/api"
    error_message = "image repository path must be <region>-docker.pkg.dev/<project>/<service>/<service>."
  }

  # WIF binding keys on the IMMUTABLE numeric repository_id, never the name.
  assert {
    condition     = google_service_account_iam_member.deploy_wif["api"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/apps-dev/attribute.repository_id/123456789"
    error_message = "the deploy SA WIF binding must use principalSet .../attribute.repository_id/<id>."
  }

  assert {
    condition     = google_service_account_iam_member.deploy_wif["api"].role == "roles/iam.workloadIdentityUser"
    error_message = "the WIF binding must grant roles/iam.workloadIdentityUser."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_condition == "assertion.repository_owner_id == \"42\""
    error_message = "the provider condition must be exactly the canonical owner pin; repo/ref/env pins live in the bindings."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_mapping["attribute.repository_id"] == "assertion.repository_id"
    error_message = "the provider must map attribute.repository_id from the token."
  }

  # Deploy SA: exactly run.developer on the service, writer on the repo, actAs on the runtime SA.
  assert {
    condition     = google_cloud_run_v2_service_iam_member.deploy["api"].role == "roles/run.developer"
    error_message = "the deploy SA must get roles/run.developer on its own service."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.deploy["api"].role == "roles/artifactregistry.writer"
    error_message = "the deploy SA must get roles/artifactregistry.writer on its own repo."
  }

  assert {
    condition     = google_service_account_iam_member.deploy_act_as_runtime["api"].role == "roles/iam.serviceAccountUser" && google_service_account_iam_member.deploy_act_as_runtime["api"].member == "serviceAccount:api-deploy@acme-dev-host-abcd.iam.gserviceaccount.com"
    error_message = "the deploy SA must get serviceAccountUser on the runtime SA only."
  }

  # Least privilege: runtime SA gets secretAccessor on its declared secret and nothing project-wide.
  assert {
    condition     = google_secret_manager_secret_iam_member.runtime["api/API_KEY"].secret_id == "api-key" && google_secret_manager_secret_iam_member.runtime["api/API_KEY"].member == "serviceAccount:api-run@acme-dev-host-abcd.iam.gserviceaccount.com"
    error_message = "the runtime SA must get secretAccessor on exactly the secrets it references."
  }

  assert {
    condition     = length(google_project_iam_member.runtime_extra) == 0 && length(google_project_iam_member.runtime_sql) == 0
    error_message = "the runtime SA must get no project-level roles by default."
  }

  assert {
    condition     = output.github_actions["api"].GCP_WIF_PROVIDER == "projects/222222222222/locations/global/workloadIdentityPools/apps-dev/providers/github"
    error_message = "github_actions must expose the full WIF provider resource name."
  }
}

# The provider condition is the owner pin only, whatever the services declare;
# each service's ref / environment pin is enforced by the attribute its deploy
# SA is bound to. The composite attributes are mapped for every service.
run "condition_is_owner_only_with_mixed_services" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services = {
      api = { github = { repository_id = "123", ref = "refs/heads/main", environment = "dev" } }
      web = { github = { repository_id = "456" } }
    }
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_condition == "assertion.repository_owner_id == \"42\""
    error_message = "the provider condition must be exactly assertion.repository_owner_id == \"<id>\"."
  }

  assert {
    condition = (
      google_iam_workload_identity_pool_provider.github[0].attribute_mapping["attribute.repo_ref"] == "assertion.repository_id + '/' + assertion.ref" &&
      google_iam_workload_identity_pool_provider.github[0].attribute_mapping["attribute.repo_env"] == "assertion.repository_id + '/' + (has(assertion.environment) ? assertion.environment : '-')" &&
      google_iam_workload_identity_pool_provider.github[0].attribute_mapping["attribute.repo_ref_env"] == "assertion.repository_id + '/' + assertion.ref + '/' + (has(assertion.environment) ? assertion.environment : '-')"
    )
    error_message = "the provider must map the repo_ref, repo_env and repo_ref_env composite attributes."
  }
}

# Declares ref + environment -> bound on attribute.repo_ref_env.
run "ref_and_env_service_binds_repo_ref_env" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services = {
      api = { github = { repository_id = "123", ref = "refs/heads/main", environment = "prod" } }
    }
  }

  assert {
    condition     = google_service_account_iam_member.deploy_wif["api"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/apps-dev/attribute.repo_ref_env/123/refs/heads/main/prod"
    error_message = "a service declaring ref and environment must bind attribute.repo_ref_env/<repo>/<ref>/<env>."
  }
}

# Declares ref only -> bound on attribute.repo_ref.
run "ref_only_service_binds_repo_ref" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services = {
      api = { github = { repository_id = "123", ref = "refs/tags/v1.2.3" } }
    }
  }

  assert {
    condition     = google_service_account_iam_member.deploy_wif["api"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/apps-dev/attribute.repo_ref/123/refs/tags/v1.2.3"
    error_message = "a service declaring only ref must bind attribute.repo_ref/<repo>/<ref>."
  }
}

# Declares environment only -> bound on attribute.repo_env.
run "env_only_service_binds_repo_env" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services = {
      api = { github = { repository_id = "123", environment = "prod" } }
    }
  }

  assert {
    condition     = google_service_account_iam_member.deploy_wif["api"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/apps-dev/attribute.repo_env/123/prod"
    error_message = "a service declaring only environment must bind attribute.repo_env/<repo>/<env>."
  }
}

# Declares neither -> bound on attribute.repository_id (any ref, any env).
run "bare_service_binds_repository_id" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services = {
      api = { github = { repository_id = "123" } }
    }
  }

  assert {
    condition     = google_service_account_iam_member.deploy_wif["api"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/apps-dev/attribute.repository_id/123"
    error_message = "a service declaring neither ref nor environment must bind attribute.repository_id/<repo>."
  }
}

# Cloud SQL: private IP only, IAM auth, runtime SA as the IAM DB user.
run "database_private_ip_iam_auth" {
  command = plan

  variables {
    services = {
      api = {
        database = { databases = ["orders"] }
      }
    }
  }

  assert {
    condition     = module.database["api"].public_ip_enabled == false
    error_message = "the instance must be private-IP only (no public IPv4)."
  }

  assert {
    condition     = module.database["api"].private_network == "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
    error_message = "the instance must peer into the ENV host VPC (where the host stage creates PSA), not the hub."
  }

  assert {
    condition     = module.database["api"].name == "api-db"
    error_message = "the instance must be named <service>-db."
  }

  assert {
    condition     = output.services["api"].database_iam_user == "api-run@acme-dev-host-abcd.iam"
    error_message = "the runtime SA must be the IAM database user (email minus .gserviceaccount.com)."
  }

  assert {
    condition     = google_project_iam_member.runtime_sql["api/client"].condition[0].expression == "resource.name == \"projects/acme-dev-host-abcd/instances/api-db\""
    error_message = "cloudsql.client must be conditioned to the service's own instance."
  }

  assert {
    condition     = contains(keys(google_project_service.this), "sqladmin.googleapis.com")
    error_message = "declaring a database must enable sqladmin.googleapis.com."
  }
}

run "gke_autopilot_opt_in" {
  command = plan

  variables {
    enable_gke_autopilot = true
  }

  assert {
    condition     = length(module.gke) == 1 && output.gke_cluster_name == "dev-apps"
    error_message = "enable_gke_autopilot must create one cluster named <env>-apps."
  }
}

# Artifact Registry images are vulnerability-scanned on push by default.
run "registry_vulnerability_scanning_on_by_default" {
  command = plan

  variables {
    services = { api = {} }
  }

  assert {
    condition     = contains(keys(google_project_service.this), "containerscanning.googleapis.com") && !contains(keys(google_project_service.this), "ondemandscanning.googleapis.com")
    error_message = "a declared service must enable the Container Scanning API (and not on-demand scanning) by default."
  }

  assert {
    condition     = module.registry["api"].vulnerability_scanning_enabled
    error_message = "the service repository must be configured for automatic vulnerability scanning."
  }
}

run "registry_vulnerability_scanning_can_be_disabled" {
  command = plan

  variables {
    services                      = { api = {} }
    enable_vulnerability_scanning = false
    enable_on_demand_scanning     = true
  }

  assert {
    condition     = !contains(keys(google_project_service.this), "containerscanning.googleapis.com") && contains(keys(google_project_service.this), "ondemandscanning.googleapis.com") && !module.registry["api"].vulnerability_scanning_enabled
    error_message = "enable_vulnerability_scanning = false must drop the Container Scanning API; enable_on_demand_scanning adds the On-Demand Scanning API."
  }
}

# First revision image: the public sample by default, overridable per stage
# (bootstrap_image, e.g. a mirror inside the VPC-SC perimeter) and per service.
run "bootstrap_image_default_and_override" {
  command = plan

  variables {
    bootstrap_image = "europe-west1-docker.pkg.dev/acme-dev-host-abcd/mirror/hello:bootstrap"
    services = {
      api    = {}
      worker = { image = "europe-west1-docker.pkg.dev/acme-dev-host-abcd/worker/worker:v1" }
    }
  }

  assert {
    condition     = output.services["api"].initial_image == "europe-west1-docker.pkg.dev/acme-dev-host-abcd/mirror/hello:bootstrap"
    error_message = "A service without image must run bootstrap_image first."
  }

  assert {
    condition     = output.services["worker"].initial_image == "europe-west1-docker.pkg.dev/acme-dev-host-abcd/worker/worker:v1"
    error_message = "A service's own image must win over bootstrap_image."
  }
}

run "bootstrap_image_defaults_to_public_sample" {
  command = plan

  variables {
    services = { api = {} }
  }

  assert {
    condition     = output.services["api"].initial_image == "us-docker.pkg.dev/cloudrun/container/hello"
    error_message = "bootstrap_image must default to the public Cloud Run sample."
  }
}

# ── Per-service observability ────────────────────────────────────────────────

run "alerts_default_per_service" {
  command = plan

  variables {
    services = { api = {} }
  }

  assert {
    condition = (
      keys(google_monitoring_alert_policy.error_ratio) == ["api"] &&
      keys(google_monitoring_alert_policy.latency_p99) == ["api"] &&
      contains(keys(google_project_service.this), "monitoring.googleapis.com")
    )
    error_message = "every service must get a 5xx-ratio and a p99-latency alert policy by default (and the Monitoring API)."
  }

  # The 5xx condition is a RATIO scoped to this service's revisions.
  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.error_ratio["api"].conditions[0].condition_threshold[0].filter, "resource.labels.service_name = \"api\"") &&
      strcontains(google_monitoring_alert_policy.error_ratio["api"].conditions[0].condition_threshold[0].filter, "metric.labels.response_code_class = \"5xx\"") &&
      strcontains(google_monitoring_alert_policy.error_ratio["api"].conditions[0].condition_threshold[0].denominator_filter, "resource.labels.service_name = \"api\"") &&
      !strcontains(google_monitoring_alert_policy.error_ratio["api"].conditions[0].condition_threshold[0].denominator_filter, "5xx") &&
      google_monitoring_alert_policy.error_ratio["api"].conditions[0].condition_threshold[0].threshold_value == 0.05 &&
      google_monitoring_alert_policy.error_ratio["api"].conditions[0].condition_threshold[0].comparison == "COMPARISON_GT"
    )
    error_message = "the 5xx alert must be a 5xx / all-requests ratio > 0.05 on this service only."
  }

  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.latency_p99["api"].conditions[0].condition_threshold[0].filter, "run.googleapis.com/request_latencies") &&
      strcontains(google_monitoring_alert_policy.latency_p99["api"].conditions[0].condition_threshold[0].filter, "resource.labels.service_name = \"api\"") &&
      google_monitoring_alert_policy.latency_p99["api"].conditions[0].condition_threshold[0].aggregations[0].per_series_aligner == "ALIGN_PERCENTILE_99" &&
      google_monitoring_alert_policy.latency_p99["api"].conditions[0].condition_threshold[0].threshold_value == 2000
    )
    error_message = "the latency alert must be p99 request latency > 2000ms on this service only."
  }

  assert {
    condition     = length(google_monitoring_alert_policy.error_ratio["api"].notification_channels) == 0 && google_monitoring_alert_policy.error_ratio["api"].user_labels["service"] == "api"
    error_message = "with no alert_notification_channel_ids the policies must have no channels, and carry the service label."
  }

  assert {
    condition = (
      length(google_pubsub_topic.service) == 0 && length(google_pubsub_subscription.service) == 0 &&
      length(google_pubsub_topic_iam_member.runtime_publisher) == 0 &&
      !contains(keys(google_project_service.this), "pubsub.googleapis.com") &&
      output.services["api"].pubsub_topic == null
    )
    error_message = "no Pub/Sub resources (or API) unless the service enables pubsub."
  }
}

run "alerts_channels_thresholds_and_opt_out" {
  command = plan

  variables {
    alert_notification_channel_ids = ["projects/acme-dev-host-abcd/notificationChannels/1234"]
    services = {
      api    = { alerts = { p99_latency_ms = 500, error_ratio_threshold = 0.01 } }
      worker = { alerts = { enabled = false } }
    }
  }

  assert {
    condition     = keys(google_monitoring_alert_policy.error_ratio) == ["api"] && keys(google_monitoring_alert_policy.latency_p99) == ["api"] && length(output.services["worker"].alert_policy_ids) == 0
    error_message = "alerts.enabled = false must drop that service's alert policies only."
  }

  assert {
    condition = (
      google_monitoring_alert_policy.latency_p99["api"].conditions[0].condition_threshold[0].threshold_value == 500 &&
      google_monitoring_alert_policy.error_ratio["api"].conditions[0].condition_threshold[0].threshold_value == 0.01 &&
      tolist(google_monitoring_alert_policy.error_ratio["api"].notification_channels) == tolist(["projects/acme-dev-host-abcd/notificationChannels/1234"]) &&
      tolist(google_monitoring_alert_policy.latency_p99["api"].notification_channels) == tolist(["projects/acme-dev-host-abcd/notificationChannels/1234"])
    )
    error_message = "custom thresholds and notification channels must reach the policies."
  }
}

run "alerts_disabled_stage_wide" {
  command = plan

  variables {
    enable_alerts = false
    services      = { api = {} }
  }

  assert {
    condition     = length(google_monitoring_alert_policy.error_ratio) == 0 && length(google_monitoring_alert_policy.latency_p99) == 0 && !contains(keys(google_project_service.this), "monitoring.googleapis.com")
    error_message = "enable_alerts = false must create no alert policies and not enable the Monitoring API."
  }
}

# ── Per-service Pub/Sub ──────────────────────────────────────────────────────

run "pubsub_enabled_least_privilege" {
  command = plan

  override_resource {
    target          = google_pubsub_topic.dead_letter
    override_during = plan
    values          = { id = "projects/acme-dev-host-abcd/topics/api-dlq" }
  }

  override_resource {
    target          = google_pubsub_topic.service
    override_during = plan
    values          = { id = "projects/acme-dev-host-abcd/topics/api" }
  }

  variables {
    services = {
      api    = { pubsub = { enabled = true, max_delivery_attempts = 10 } }
      worker = {}
    }
  }

  assert {
    condition = (
      keys(google_pubsub_topic.service) == ["api"] &&
      google_pubsub_topic.service["api"].name == "api" &&
      google_pubsub_topic.dead_letter["api"].name == "api-dlq" &&
      google_pubsub_subscription.service["api"].name == "api-sub" &&
      google_pubsub_subscription.service["api"].topic == "projects/acme-dev-host-abcd/topics/api" &&
      google_pubsub_subscription.dead_letter["api"].topic == "projects/acme-dev-host-abcd/topics/api-dlq" &&
      contains(keys(google_project_service.this), "pubsub.googleapis.com")
    )
    error_message = "pubsub.enabled must create topic <name>, subscription <name>-sub and dead-letter topic <name>-dlq with a retaining subscription."
  }

  assert {
    condition = (
      google_pubsub_subscription.service["api"].dead_letter_policy[0].dead_letter_topic == "projects/acme-dev-host-abcd/topics/api-dlq" &&
      google_pubsub_subscription.service["api"].dead_letter_policy[0].max_delivery_attempts == 10 &&
      google_pubsub_subscription.service["api"].expiration_policy[0].ttl == ""
    )
    error_message = "the subscription must dead-letter to its own DLQ after max_delivery_attempts and never expire."
  }

  # Runtime SA: publisher on ITS topic, subscriber on ITS subscription — no
  # project-level Pub/Sub role, nothing for the service without pubsub.
  assert {
    condition = (
      keys(google_pubsub_topic_iam_member.runtime_publisher) == ["api"] &&
      google_pubsub_topic_iam_member.runtime_publisher["api"].topic == "api" &&
      google_pubsub_topic_iam_member.runtime_publisher["api"].role == "roles/pubsub.publisher" &&
      google_pubsub_topic_iam_member.runtime_publisher["api"].member == "serviceAccount:api-run@acme-dev-host-abcd.iam.gserviceaccount.com" &&
      keys(google_pubsub_subscription_iam_member.runtime_subscriber) == ["api"] &&
      google_pubsub_subscription_iam_member.runtime_subscriber["api"].subscription == "api-sub" &&
      google_pubsub_subscription_iam_member.runtime_subscriber["api"].role == "roles/pubsub.subscriber" &&
      google_pubsub_subscription_iam_member.runtime_subscriber["api"].member == "serviceAccount:api-run@acme-dev-host-abcd.iam.gserviceaccount.com" &&
      length(google_project_iam_member.runtime_extra) == 0
    )
    error_message = "the runtime SA must get publisher on its own topic and subscriber on its own subscription only."
  }

  assert {
    condition = (
      google_pubsub_topic_iam_member.agent_dead_letter_publisher["api"].topic == "api-dlq" &&
      google_pubsub_topic_iam_member.agent_dead_letter_publisher["api"].member == "serviceAccount:service-222222222222@gcp-sa-pubsub.iam.gserviceaccount.com" &&
      google_pubsub_subscription_iam_member.agent_source_subscriber["api"].subscription == "api-sub" &&
      google_pubsub_subscription_iam_member.agent_source_subscriber["api"].member == "serviceAccount:service-222222222222@gcp-sa-pubsub.iam.gserviceaccount.com"
    )
    error_message = "the Pub/Sub service agent must be able to forward dead letters (publisher on the DLQ, subscriber on the source subscription)."
  }

  assert {
    condition = (
      output.services["api"].pubsub_topic == "projects/acme-dev-host-abcd/topics/api" &&
      output.services["api"].pubsub_subscription == "projects/acme-dev-host-abcd/subscriptions/api-sub" &&
      output.services["api"].pubsub_dead_letter_topic == "projects/acme-dev-host-abcd/topics/api-dlq" &&
      output.services["worker"].pubsub_topic == null
    )
    error_message = "the services output must expose the topic, subscription and dead-letter topic."
  }

  assert {
    condition     = google_pubsub_topic.service["api"].kms_key_name == null
    error_message = "topics use Google-managed encryption unless pubsub_kms_key_name is set."
  }
}

run "pubsub_with_cmek" {
  command = plan

  variables {
    pubsub_kms_key_name = "projects/acme-sec/locations/europe-west1/keyRings/apps/cryptoKeys/pubsub"
    services            = { api = { pubsub = { enabled = true } } }
  }

  assert {
    condition = (
      google_pubsub_topic.service["api"].kms_key_name == var.pubsub_kms_key_name &&
      google_pubsub_topic.dead_letter["api"].kms_key_name == var.pubsub_kms_key_name
    )
    error_message = "pubsub_kms_key_name must encrypt both the topic and the dead-letter topic."
  }
}
