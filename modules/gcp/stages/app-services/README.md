# App Services Stage (the application golden path)

One `services` map entry gives a service team, in the environment host project:

- an Artifact Registry docker repo (immutable tags, cleanup policies, optional CMEK);
- a least-privilege runtime service account (`<svc>-run`);
- a Cloud Run v2 service (internal ingress by default, Direct VPC egress to the
  env Shared VPC subnet, min 0 instances, secrets from Secret Manager, optional
  Binary Authorization);
- optionally, a private-IP Cloud SQL Postgres (`<svc>-db`) on the env VPC's
  Private Service Access, with IAM auth and the runtime SA as its IAM DB user;
- optionally, a deploy service account (`<svc>-deploy`) impersonable only by
  GitHub Actions from the repo's immutable numeric `repository_id` (optionally a
  ref and/or GitHub environment), through an app-only WIF pool in the host project.

An optional environment-level GKE Autopilot cluster is behind `enable_gke_autopilot`.
The default (`services = {}`, every flag off) creates nothing.

It is called once from [`envs/gcp/workload`](../../../../envs/gcp/workload/main.tf)
(`module "app_services"`). Walkthrough:
[`docs/guides/deploying-a-service.md`](../../../../docs/guides/deploying-a-service.md).

## Usage

```hcl
module "app_services" {
  source = "../../../modules/gcp/stages/app-services"

  project_id     = local.env_config.host_project_id
  project_number = local.env_config.host_project_number
  region         = local.env_config.region
  environment    = var.environment
  network_id     = module.host.network_id
  subnetwork_id  = values(module.host.subnets.private)[0].id

  enable_app_deploy_wif = true
  services = {
    orders-api = {
      secrets  = { STRIPE_API_KEY = { secret = "orders-api-stripe-key" } }
      database = { databases = ["orders"] }
      github   = { repository_id = "987654321", ref = "refs/heads/main" }
    }
  }

  depends_on = [module.host] # PSA must exist before Cloud SQL
}
```

<!-- BEGIN_TF_DOCS -->
Copyright 2026 Ashes

App Services Stage - the application golden path.

A service team adds one entry to var.services and gets, in the environment host
project: an Artifact Registry docker repo, a least-privilege runtime SA, a Cloud
Run v2 service (internal ingress, Direct VPC egress, scale-to-zero, secrets from
Secret Manager), an optional private-IP Cloud SQL Postgres with IAM auth, and an
optional GitHub deploy identity (WIF, bound on the immutable repository\_id),
per-service Cloud Monitoring alert policies (5xx ratio, p99 latency), an
optional SLO (availability or latency, with an optional burn-rate alert) and an
optional Pub/Sub topic + subscription + dead-letter topic.
A service with runtime = "cloud-run-job" gets a Cloud Run v2 job (run to
completion, no URL) instead of a service; request alerts and SLOs apply only to
Cloud Run services.
An optional GKE Autopilot cluster is available at environment level.
Everything is behind flags: the default (services = {}) creates nothing.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	environment =
	project_id =
	region =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |

## Modules


- database - ../../data/cloud-sql
- gke - ../../compute/gke-autopilot
- job - ../../compute/cloud-run-job
- registry - ../../artifact-registry
- service - ../../compute/cloud-run
- slo - ../../monitoring/slo


## Resources

The following resources are created:


- resource.google_artifact_registry_repository_iam_member.deploy (modules/gcp/stages/app-services/main.tf#L582)
- resource.google_cloud_run_v2_job_iam_member.deploy (modules/gcp/stages/app-services/main.tf#L570)
- resource.google_cloud_run_v2_job_iam_member.invoker (modules/gcp/stages/app-services/main.tf#L384)
- resource.google_cloud_run_v2_service_iam_member.deploy (modules/gcp/stages/app-services/main.tf#L558)
- resource.google_cloud_run_v2_service_iam_member.invoker (modules/gcp/stages/app-services/main.tf#L327)
- resource.google_compute_subnetwork_iam_member.serverless_network_user (modules/gcp/stages/app-services/main.tf#L467)
- resource.google_iam_workload_identity_pool.apps (modules/gcp/stages/app-services/main.tf#L489)
- resource.google_iam_workload_identity_pool_provider.github (modules/gcp/stages/app-services/main.tf#L500)
- resource.google_monitoring_alert_policy.error_ratio (modules/gcp/stages/app-services/main.tf#L614)
- resource.google_monitoring_alert_policy.latency_p99 (modules/gcp/stages/app-services/main.tf#L666)
- resource.google_monitoring_service.slo (modules/gcp/stages/app-services/main.tf#L719)
- resource.google_project_iam_member.runtime_extra (modules/gcp/stages/app-services/main.tf#L265)
- resource.google_project_iam_member.runtime_sql (modules/gcp/stages/app-services/main.tf#L435)
- resource.google_project_iam_member.serverless_network_viewer (modules/gcp/stages/app-services/main.tf#L477)
- resource.google_project_service.this (modules/gcp/stages/app-services/main.tf#L180)
- resource.google_pubsub_subscription.dead_letter (modules/gcp/stages/app-services/main.tf#L814)
- resource.google_pubsub_subscription.service (modules/gcp/stages/app-services/main.tf#L786)
- resource.google_pubsub_subscription_iam_member.agent_source_subscriber (modules/gcp/stages/app-services/main.tf#L864)
- resource.google_pubsub_subscription_iam_member.runtime_subscriber (modules/gcp/stages/app-services/main.tf#L842)
- resource.google_pubsub_topic.dead_letter (modules/gcp/stages/app-services/main.tf#L775)
- resource.google_pubsub_topic.service (modules/gcp/stages/app-services/main.tf#L764)
- resource.google_pubsub_topic_iam_member.agent_dead_letter_publisher (modules/gcp/stages/app-services/main.tf#L855)
- resource.google_pubsub_topic_iam_member.runtime_publisher (modules/gcp/stages/app-services/main.tf#L831)
- resource.google_secret_manager_secret_iam_member.runtime (modules/gcp/stages/app-services/main.tf#L254)
- resource.google_service_account.deploy (modules/gcp/stages/app-services/main.tf#L535)
- resource.google_service_account.runtime (modules/gcp/stages/app-services/main.tf#L243)
- resource.google_service_account_iam_member.deploy_act_as_runtime (modules/gcp/stages/app-services/main.tf#L595)
- resource.google_service_account_iam_member.deploy_wif (modules/gcp/stages/app-services/main.tf#L548)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod, ...). Used in default names and labels. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The environment host project ID. Every app resource (registry, service accounts, Cloud Run, Cloud SQL, WIF pool, GKE) is created here. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region for the Artifact Registry repositories, Cloud Run services, Cloud SQL instances and the GKE cluster (the environment region). | `string` | n/a | yes |
| <a name="input_alert_notification_channel_ids"></a> [alert\_notification\_channel\_ids](#input\_alert\_notification\_channel\_ids) | Existing Cloud Monitoring notification channels (projects/<p>/notificationChannels/<id>) every service alert policy notifies. Empty creates the policies with no channel (incidents are visible in the console only). | `list(string)` | `[]` | no |
| <a name="input_app_deploy_wif_pool_id"></a> [app\_deploy\_wif\_pool\_id](#input\_app\_deploy\_wif\_pool\_id) | ID of the app-deploy Workload Identity pool. Null defaults to "apps-<environment>" (truncated to 32 chars). Pool IDs stay reserved for 30 days after deletion. | `string` | `null` | no |
| <a name="input_artifact_registry_kms_key_name"></a> [artifact\_registry\_kms\_key\_name](#input\_artifact\_registry\_kms\_key\_name) | Optional CMEK (projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>) for every service's Artifact Registry repository. Null uses Google-managed encryption. The Artifact Registry service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on the key first. | `string` | `null` | no |
| <a name="input_bootstrap_image"></a> [bootstrap\_image](#input\_bootstrap\_image) | Image the FIRST Cloud Run revision of a service runs when its `image` is null (CI deploys replace it). The default, Google's public sample us-docker.pkg.dev/cloudrun/container/hello, lives OUTSIDE your project: a VPC-SC perimeter that restricts artifactregistry.googleapis.com, or a Binary Authorization policy, blocks it. In that case mirror a placeholder into a repo inside the perimeter (e.g. <region>-docker.pkg.dev/<host-project>/<repo>/hello:bootstrap) and set this (gcp.workload.bootstrap\_image in config/landing-zone.yaml). | `string` | `"us-docker.pkg.dev/cloudrun/container/hello"` | no |
| <a name="input_enable_alerts"></a> [enable\_alerts](#input\_enable\_alerts) | Create per-service Cloud Monitoring alert policies (Cloud Run 5xx ratio and p99 latency; thresholds and per-service opt-out in services[*].alerts) and enable monitoring.googleapis.com. Only takes effect when services is non-empty. | `bool` | `true` | no |
| <a name="input_enable_app_deploy_wif"></a> [enable\_app\_deploy\_wif](#input\_enable\_app\_deploy\_wif) | Create a Workload Identity pool for APPLICATION deploys in the host project (separate from the infra pool in gcp-bootstrap), with one GitHub OIDC provider. Required for any service that sets `github`. | `bool` | `false` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Default deletion protection for Cloud Run services, Cloud SQL instances and the GKE cluster. Per-service `enable_deletion_protection` / `database.enable_deletion_protection` override it. | `bool` | `true` | no |
| <a name="input_enable_gke_autopilot"></a> [enable\_gke\_autopilot](#input\_enable\_gke\_autopilot) | Create one private GKE Autopilot cluster for the environment on var.subnetwork\_id. Default off. | `bool` | `false` | no |
| <a name="input_enable_on_demand_scanning"></a> [enable\_on\_demand\_scanning](#input\_enable\_on\_demand\_scanning) | Also enable ondemandscanning.googleapis.com so CI can scan images before pushing (`gcloud artifacts docker images scan`). Default false. | `bool` | `false` | no |
| <a name="input_enable_project_services"></a> [enable\_project\_services](#input\_enable\_project\_services) | Enable the Google APIs the declared resources need (run, artifactregistry, sqladmin, secretmanager, iamcredentials, sts, container) on the host project. Only APIs for features actually in use are enabled; disable\_on\_destroy is false. | `bool` | `true` | no |
| <a name="input_enable_vulnerability_scanning"></a> [enable\_vulnerability\_scanning](#input\_enable\_vulnerability\_scanning) | Scan every service's container images automatically on push (Artifact Analysis): enables containerscanning.googleapis.com (with enable\_project\_services) and sets each repository's vulnerability scanning to INHERITED. Billed per scanned image. Default true. | `bool` | `true` | no |
| <a name="input_github_repository_owner_id"></a> [github\_repository\_owner\_id](#input\_github\_repository\_owner\_id) | IMMUTABLE numeric GitHub organization/user ID (gh api orgs/<org> --jq .id). Required once a service declares `github`: the provider attribute\_condition is exactly assertion.repository\_owner\_id == "<id>", the form the org-policy constraint custom.wifProviderTenantPinned accepts. | `string` | `null` | no |
| <a name="input_gke_cluster_name"></a> [gke\_cluster\_name](#input\_gke\_cluster\_name) | Name of the GKE Autopilot cluster. Null defaults to "<environment>-apps". | `string` | `null` | no |
| <a name="input_gke_cluster_secondary_range_name"></a> [gke\_cluster\_secondary\_range\_name](#input\_gke\_cluster\_secondary\_range\_name) | Subnet secondary range name for pod IPs. Null lets GKE allocate one. | `string` | `null` | no |
| <a name="input_gke_master_authorized_networks"></a> [gke\_master\_authorized\_networks](#input\_gke\_master\_authorized\_networks) | CIDR blocks allowed to reach the GKE control plane. | <pre>list(object({<br/>    cidr_block   = string<br/>    display_name = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_gke_master_ipv4_cidr_block"></a> [gke\_master\_ipv4\_cidr\_block](#input\_gke\_master\_ipv4\_cidr\_block) | The /28 control-plane CIDR for the GKE cluster. Must not overlap any range in the VPC or its peers. | `string` | `"172.16.0.0/28"` | no |
| <a name="input_gke_services_secondary_range_name"></a> [gke\_services\_secondary\_range\_name](#input\_gke\_services\_secondary\_range\_name) | Subnet secondary range name for Service IPs. Null lets GKE allocate one. | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource. | `map(string)` | `{}` | no |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | ID of the environment Shared VPC network (projects/<p>/global/networks/<n>). Cloud SQL peers into it via the host stage's Private Service Access; Cloud Run and GKE attach to it. Required when any service or GKE is declared. | `string` | `null` | no |
| <a name="input_project_number"></a> [project\_number](#input\_project\_number) | Numeric project number of var.project\_id. Used to build the deterministic Workload Identity pool resource name (principalSet members need the number, not the ID). Required when enable\_app\_deploy\_wif = true. | `string` | `null` | no |
| <a name="input_pubsub_kms_key_name"></a> [pubsub\_kms\_key\_name](#input\_pubsub\_kms\_key\_name) | Optional CMEK (projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>) for every service topic and dead-letter topic. Null uses Google-managed encryption. The Pub/Sub service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on the key first. | `string` | `null` | no |
| <a name="input_services"></a> [services](#input\_services) | Application services, keyed by service name (2-22 chars: lowercase letters,<br/>digits, hyphens). Each entry creates, in the host project: an Artifact<br/>Registry docker repo `<name>`, a runtime SA `<name>-run`, and a Cloud Run v2<br/>service `<name>` (internal ingress, Direct VPC egress, scale-to-zero).<br/>Optional per entry:<br/>  database = {...}  -> private-IP Cloud SQL Postgres `<name>-db` with IAM auth;<br/>                       the runtime SA is its IAM database user.<br/>  project\_id / project\_number<br/>                    -> deploy this service into a team service project<br/>                       (Shared VPC subnet access is granted to its Cloud Run<br/>                       service agent). Default: the host project.<br/>  github   = {...}  -> deploy SA `<name>-deploy` bound via WIF to the GitHub<br/>                       repo's IMMUTABLE numeric repository\_id (optionally a<br/>                       ref and/or GitHub environment). Needs enable\_app\_deploy\_wif.<br/>  secrets  = { ENV\_VAR = { secret = "<secret id in the service project, or projects/<p>/secrets/<s>>" } }<br/>                       -> env vars from Secret Manager; the runtime SA gets<br/>                       secretAccessor on exactly those secrets.<br/>  runtime  = "cloud-run-job"<br/>                    -> a Cloud Run v2 job `<name>` (run to completion, no<br/>                       URL; `job` sets task\_count / parallelism / max\_retries,<br/>                       `timeout` is the task timeout) instead of a service.<br/>                       Default "cloud-run". Request alerts and SLOs apply to<br/>                       services only; a job cannot be unauthenticated.<br/>  slo      = {...}  -> an availability or latency SLO on the Cloud Run<br/>                       service (modules/gcp/monitoring/slo), optionally with<br/>                       an error-budget burn-rate alert.<br/>The default `{}` creates nothing. | <pre>map(object({<br/>    runtime                     = optional(string, "cloud-run") # cloud-run | cloud-run-job<br/>    image                       = optional(string)              # null => var.bootstrap_image<br/>    ingress                     = optional(string, "INGRESS_TRAFFIC_INTERNAL_ONLY")<br/>    cpu                         = optional(string, "1000m")<br/>    memory                      = optional(string, "512Mi")<br/>    min_instances               = optional(number, 0)<br/>    max_instances               = optional(number, 10)<br/>    concurrency                 = optional(number, 80)<br/>    timeout                     = optional(string, "300s")<br/>    env_vars                    = optional(map(string), {})<br/>    secrets                     = optional(map(object({ secret = string, version = optional(string, "latest") })), {})<br/>    subnetwork_id               = optional(string)<br/>    vpc_egress                  = optional(string, "PRIVATE_RANGES_ONLY")<br/>    enable_binary_authorization = optional(bool, false)<br/>    binary_authorization_policy = optional(string)<br/>    enable_unauthenticated      = optional(bool, false)<br/>    invoker_members             = optional(list(string), [])<br/>    runtime_project_roles       = optional(list(string), [])<br/>    enable_deletion_protection  = optional(bool)<br/>    labels                      = optional(map(string), {})<br/><br/>    # Team service project. Null = the environment host project (var.project_id).<br/>    # When set, the service's registry, runtime/deploy SAs, Cloud Run, Cloud SQL,<br/>    # alerts and Pub/Sub live in that project (it must be a Shared VPC service<br/>    # project with the run, artifactregistry and iam APIs enabled); the WIF pool<br/>    # stays in var.project_id. project_number is then required: it names the<br/>    # project's Cloud Run service agent, which is granted compute.networkUser on<br/>    # the service's subnet and compute.networkViewer on the host project.<br/>    project_id     = optional(string)<br/>    project_number = optional(string)<br/>    # Explicit override of the Shared VPC grants above. Null derives it from<br/>    # project_id; callers whose project_id is unknown until apply (a project<br/>    # created in the same run) set it to true so for_each keys stay plan-time known.<br/>    # Must be true with a project_id of another project, false only without one.<br/>    grant_network_access = optional(bool)<br/>    # Services sharing a value share ONE networkViewer and one networkUser per<br/>    # subnet (so removing a service never revokes a sibling's grant). Null = the<br/>    # service key. Set it to the team name for services of the same project.<br/>    network_access_group = optional(string)<br/><br/>    artifact_registry = optional(object({<br/>      immutable_tags             = optional(bool, true)<br/>      keep_count                 = optional(number, 20)<br/>      delete_untagged_older_than = optional(string, "604800s")<br/>      cleanup_policy_dry_run     = optional(bool, false)<br/>    }), {})<br/><br/>    database = optional(object({<br/>      database_version              = optional(string, "POSTGRES_16")<br/>      edition                       = optional(string, "ENTERPRISE")<br/>      tier                          = optional(string, "db-custom-1-3840")<br/>      databases                     = optional(list(string), ["app"])<br/>      enable_high_availability      = optional(bool, false)<br/>      enable_point_in_time_recovery = optional(bool, true)<br/>      encryption_key_name           = optional(string)<br/>      enable_deletion_protection    = optional(bool)<br/>    }))<br/><br/>    github = optional(object({<br/>      repository_id = string<br/>      repository    = optional(string)<br/>      ref           = optional(string)<br/>      environment   = optional(string)<br/>    }))<br/><br/>    # Cloud Monitoring alert policies for this service (with var.enable_alerts):<br/>    # 5xx request ratio and p99 request latency of its Cloud Run revisions.<br/>    alerts = optional(object({<br/>      enabled               = optional(bool, true)<br/>      error_ratio_threshold = optional(number, 0.05) # 5xx / all requests, (0, 1]<br/>      p99_latency_ms        = optional(number, 2000)<br/>      duration              = optional(string, "300s") # sustained before it fires<br/>    }), {})<br/><br/>    # Cloud Run job settings (runtime = "cloud-run-job" only; ignored otherwise).<br/>    job = optional(object({<br/>      task_count  = optional(number, 1)<br/>      parallelism = optional(number) # null = as many as possible<br/>      max_retries = optional(number, 3)<br/>    }), {})<br/><br/>    # Service-level objective on the Cloud Run service (runtime = "cloud-run"<br/>    # only). Null (default) creates none.<br/>    slo = optional(object({<br/>      sli_type               = optional(string, "availability") # availability | latency<br/>      goal                   = optional(number, 0.99)           # (0, 1)<br/>      rolling_period_days    = optional(number, 28)<br/>      latency_threshold      = optional(string, "1s") # latency SLI only<br/>      enable_burn_rate_alert = optional(bool, false)<br/>      burn_rate_threshold    = optional(number, 10)<br/>      burn_rate_lookback     = optional(string, "3600s")<br/>    }))<br/><br/>    # Pub/Sub topic `<name>` + pull subscription `<name>-sub` with a dead-letter<br/>    # topic `<name>-dlq` (+ `<name>-dlq-sub` so dead letters are retained). The<br/>    # runtime SA may publish to ITS topic and consume ITS subscription only;<br/>    # PUBSUB_TOPIC / PUBSUB_SUBSCRIPTION are injected as env vars.<br/>    pubsub = optional(object({<br/>      enabled                    = optional(bool, false)<br/>      ack_deadline_seconds       = optional(number, 60)<br/>      max_delivery_attempts      = optional(number, 5)<br/>      message_retention_duration = optional(string, "604800s")<br/>    }), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_subnetwork_id"></a> [subnetwork\_id](#input\_subnetwork\_id) | ID of the default Shared VPC subnet (projects/<p>/regions/<r>/subnetworks/<s>) used for Cloud Run Direct VPC egress and GKE nodes. Per-service `subnetwork_id` overrides it for Cloud Run. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_github_actions"></a> [github\_actions](#output\_github\_actions) | Per-service values to set as GitHub repository/environment variables for the delivery workflow (examples/app-delivery/cloud-run-delivery.example.yml): GCP\_WIF\_PROVIDER, GCP\_DEPLOY\_SA, GCP\_PROJECT\_ID, GCP\_REGION, CLOUD\_RUN\_SERVICE (null for a job), CLOUD\_RUN\_JOB (null for a service), IMAGE\_REPOSITORY. |
| <a name="output_gke_cluster_name"></a> [gke\_cluster\_name](#output\_gke\_cluster\_name) | Name of the environment GKE Autopilot cluster, or null when disabled. |
| <a name="output_image_repositories"></a> [image\_repositories](#output\_image\_repositories) | Artifact Registry image repository path (<region>-docker.pkg.dev/<project>/<service>/<service>) per service key. |
| <a name="output_runtime_service_account_emails"></a> [runtime\_service\_account\_emails](#output\_runtime\_service\_account\_emails) | Runtime service account email per service key. |
| <a name="output_services"></a> [services](#output\_services) | Per-service golden-path facts: runtime, Cloud Run service name and URL (null for a job) or job name (null for a service), image repository path, runtime and deploy SA emails, and (when a database is declared) the Cloud SQL connection name and IAM DB user; Pub/Sub topic / subscription / dead-letter topic when pubsub is enabled; the ids of its alert policies and its SLO name (null when none is declared). |
| <a name="output_sql_connection_names"></a> [sql\_connection\_names](#output\_sql\_connection\_names) | Cloud SQL instance connection name (<project>:<region>:<instance>) per service key that declares a database. |
| <a name="output_urls"></a> [urls](#output\_urls) | Cloud Run service URL per service key (Cloud Run services only; jobs have no URL). |
| <a name="output_workload_identity_pool_name"></a> [workload\_identity\_pool\_name](#output\_workload\_identity\_pool\_name) | Full resource name of the app-deploy Workload Identity pool, or null when enable\_app\_deploy\_wif = false. |
| <a name="output_workload_identity_provider"></a> [workload\_identity\_provider](#output\_workload\_identity\_provider) | Full resource name of the GitHub OIDC provider (the google-github-actions/auth `workload_identity_provider` input), or null until a service declares `github`. |
<!-- END_TF_DOCS -->
