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
optional GitHub deploy identity (WIF, bound on the immutable repository\_id).
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
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |

## Modules


- database - ../../data/cloud-sql
- gke - ../../compute/gke-autopilot
- registry - ../../artifact-registry
- service - ../../compute/cloud-run


## Resources

The following resources are created:


- resource.google_artifact_registry_repository_iam_member.deploy (modules/gcp/stages/app-services/main.tf#L371)
- resource.google_cloud_run_v2_service_iam_member.deploy (modules/gcp/stages/app-services/main.tf#L359)
- resource.google_cloud_run_v2_service_iam_member.invoker (modules/gcp/stages/app-services/main.tf#L222)
- resource.google_iam_workload_identity_pool.apps (modules/gcp/stages/app-services/main.tf#L298)
- resource.google_iam_workload_identity_pool_provider.github (modules/gcp/stages/app-services/main.tf#L309)
- resource.google_project_iam_member.runtime_extra (modules/gcp/stages/app-services/main.tf#L156)
- resource.google_project_iam_member.runtime_sql (modules/gcp/stages/app-services/main.tf#L273)
- resource.google_project_service.this (modules/gcp/stages/app-services/main.tf#L82)
- resource.google_secret_manager_secret_iam_member.runtime (modules/gcp/stages/app-services/main.tf#L145)
- resource.google_service_account.deploy (modules/gcp/stages/app-services/main.tf#L337)
- resource.google_service_account.runtime (modules/gcp/stages/app-services/main.tf#L134)
- resource.google_service_account_iam_member.deploy_act_as_runtime (modules/gcp/stages/app-services/main.tf#L384)
- resource.google_service_account_iam_member.deploy_wif (modules/gcp/stages/app-services/main.tf#L349)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod, ...). Used in default names and labels. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The environment host project ID. Every app resource (registry, service accounts, Cloud Run, Cloud SQL, WIF pool, GKE) is created here. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region for the Artifact Registry repositories, Cloud Run services, Cloud SQL instances and the GKE cluster (the environment region). | `string` | n/a | yes |
| <a name="input_app_deploy_wif_pool_id"></a> [app\_deploy\_wif\_pool\_id](#input\_app\_deploy\_wif\_pool\_id) | ID of the app-deploy Workload Identity pool. Null defaults to "apps-<environment>" (truncated to 32 chars). Pool IDs stay reserved for 30 days after deletion. | `string` | `null` | no |
| <a name="input_artifact_registry_kms_key_name"></a> [artifact\_registry\_kms\_key\_name](#input\_artifact\_registry\_kms\_key\_name) | Optional CMEK (projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>) for every service's Artifact Registry repository. Null uses Google-managed encryption. The Artifact Registry service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on the key first. | `string` | `null` | no |
| <a name="input_enable_app_deploy_wif"></a> [enable\_app\_deploy\_wif](#input\_enable\_app\_deploy\_wif) | Create a Workload Identity pool for APPLICATION deploys in the host project (separate from the infra pool in gcp-bootstrap), with one GitHub OIDC provider. Required for any service that sets `github`. | `bool` | `false` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Default deletion protection for Cloud Run services, Cloud SQL instances and the GKE cluster. Per-service `enable_deletion_protection` / `database.enable_deletion_protection` override it. | `bool` | `true` | no |
| <a name="input_enable_gke_autopilot"></a> [enable\_gke\_autopilot](#input\_enable\_gke\_autopilot) | Create one private GKE Autopilot cluster for the environment on var.subnetwork\_id. Default off. | `bool` | `false` | no |
| <a name="input_enable_on_demand_scanning"></a> [enable\_on\_demand\_scanning](#input\_enable\_on\_demand\_scanning) | Also enable ondemandscanning.googleapis.com so CI can scan images before pushing (`gcloud artifacts docker images scan`). Default false. | `bool` | `false` | no |
| <a name="input_enable_project_services"></a> [enable\_project\_services](#input\_enable\_project\_services) | Enable the Google APIs the declared resources need (run, artifactregistry, sqladmin, secretmanager, iamcredentials, sts, container) on the host project. Only APIs for features actually in use are enabled; disable\_on\_destroy is false. | `bool` | `true` | no |
| <a name="input_enable_vulnerability_scanning"></a> [enable\_vulnerability\_scanning](#input\_enable\_vulnerability\_scanning) | Scan every service's container images automatically on push (Artifact Analysis): enables containerscanning.googleapis.com (with enable\_project\_services) and sets each repository's vulnerability scanning to INHERITED. Billed per scanned image. Default true. | `bool` | `true` | no |
| <a name="input_github_repository_owner_id"></a> [github\_repository\_owner\_id](#input\_github\_repository\_owner\_id) | Optional IMMUTABLE numeric GitHub organization/user ID. When set, the provider additionally rejects any token whose repository\_owner\_id differs (defence in depth on top of the per-repository\_id condition). | `string` | `null` | no |
| <a name="input_gke_cluster_name"></a> [gke\_cluster\_name](#input\_gke\_cluster\_name) | Name of the GKE Autopilot cluster. Null defaults to "<environment>-apps". | `string` | `null` | no |
| <a name="input_gke_cluster_secondary_range_name"></a> [gke\_cluster\_secondary\_range\_name](#input\_gke\_cluster\_secondary\_range\_name) | Subnet secondary range name for pod IPs. Null lets GKE allocate one. | `string` | `null` | no |
| <a name="input_gke_master_authorized_networks"></a> [gke\_master\_authorized\_networks](#input\_gke\_master\_authorized\_networks) | CIDR blocks allowed to reach the GKE control plane. | <pre>list(object({<br/>    cidr_block   = string<br/>    display_name = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_gke_master_ipv4_cidr_block"></a> [gke\_master\_ipv4\_cidr\_block](#input\_gke\_master\_ipv4\_cidr\_block) | The /28 control-plane CIDR for the GKE cluster. Must not overlap any range in the VPC or its peers. | `string` | `"172.16.0.0/28"` | no |
| <a name="input_gke_services_secondary_range_name"></a> [gke\_services\_secondary\_range\_name](#input\_gke\_services\_secondary\_range\_name) | Subnet secondary range name for Service IPs. Null lets GKE allocate one. | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource. | `map(string)` | `{}` | no |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | ID of the environment Shared VPC network (projects/<p>/global/networks/<n>). Cloud SQL peers into it via the host stage's Private Service Access; Cloud Run and GKE attach to it. Required when any service or GKE is declared. | `string` | `null` | no |
| <a name="input_project_number"></a> [project\_number](#input\_project\_number) | Numeric project number of var.project\_id. Used to build the deterministic Workload Identity pool resource name (principalSet members need the number, not the ID). Required when enable\_app\_deploy\_wif = true. | `string` | `null` | no |
| <a name="input_services"></a> [services](#input\_services) | Application services, keyed by service name (2-22 chars: lowercase letters,<br/>digits, hyphens). Each entry creates, in the host project: an Artifact<br/>Registry docker repo `<name>`, a runtime SA `<name>-run`, and a Cloud Run v2<br/>service `<name>` (internal ingress, Direct VPC egress, scale-to-zero).<br/>Optional per entry:<br/>  database = {...}  -> private-IP Cloud SQL Postgres `<name>-db` with IAM auth;<br/>                       the runtime SA is its IAM database user.<br/>  github   = {...}  -> deploy SA `<name>-deploy` bound via WIF to the GitHub<br/>                       repo's IMMUTABLE numeric repository\_id (optionally a<br/>                       ref and/or GitHub environment). Needs enable\_app\_deploy\_wif.<br/>  secrets  = { ENV\_VAR = { secret = "<secret id in the host project>" } }<br/>                       -> env vars from Secret Manager; the runtime SA gets<br/>                       secretAccessor on exactly those secrets.<br/>The default `{}` creates nothing. | <pre>map(object({<br/>    image                       = optional(string, "us-docker.pkg.dev/cloudrun/container/hello")<br/>    ingress                     = optional(string, "INGRESS_TRAFFIC_INTERNAL_ONLY")<br/>    cpu                         = optional(string, "1000m")<br/>    memory                      = optional(string, "512Mi")<br/>    min_instances               = optional(number, 0)<br/>    max_instances               = optional(number, 10)<br/>    concurrency                 = optional(number, 80)<br/>    timeout                     = optional(string, "300s")<br/>    env_vars                    = optional(map(string), {})<br/>    secrets                     = optional(map(object({ secret = string, version = optional(string, "latest") })), {})<br/>    subnetwork_id               = optional(string)<br/>    vpc_egress                  = optional(string, "PRIVATE_RANGES_ONLY")<br/>    enable_binary_authorization = optional(bool, false)<br/>    binary_authorization_policy = optional(string)<br/>    enable_unauthenticated      = optional(bool, false)<br/>    invoker_members             = optional(list(string), [])<br/>    runtime_project_roles       = optional(list(string), [])<br/>    enable_deletion_protection  = optional(bool)<br/>    labels                      = optional(map(string), {})<br/><br/>    artifact_registry = optional(object({<br/>      immutable_tags             = optional(bool, true)<br/>      keep_count                 = optional(number, 20)<br/>      delete_untagged_older_than = optional(string, "604800s")<br/>      cleanup_policy_dry_run     = optional(bool, false)<br/>    }), {})<br/><br/>    database = optional(object({<br/>      database_version              = optional(string, "POSTGRES_16")<br/>      edition                       = optional(string, "ENTERPRISE")<br/>      tier                          = optional(string, "db-custom-1-3840")<br/>      databases                     = optional(list(string), ["app"])<br/>      enable_high_availability      = optional(bool, false)<br/>      enable_point_in_time_recovery = optional(bool, true)<br/>      encryption_key_name           = optional(string)<br/>      enable_deletion_protection    = optional(bool)<br/>    }))<br/><br/>    github = optional(object({<br/>      repository_id = string<br/>      repository    = optional(string)<br/>      ref           = optional(string)<br/>      environment   = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_subnetwork_id"></a> [subnetwork\_id](#input\_subnetwork\_id) | ID of the default Shared VPC subnet (projects/<p>/regions/<r>/subnetworks/<s>) used for Cloud Run Direct VPC egress and GKE nodes. Per-service `subnetwork_id` overrides it for Cloud Run. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_github_actions"></a> [github\_actions](#output\_github\_actions) | Per-service values to set as GitHub repository/environment variables for the delivery workflow (examples/app-delivery/cloud-run-delivery.example.yml): GCP\_WIF\_PROVIDER, GCP\_DEPLOY\_SA, GCP\_PROJECT\_ID, GCP\_REGION, CLOUD\_RUN\_SERVICE, IMAGE\_REPOSITORY. |
| <a name="output_gke_cluster_name"></a> [gke\_cluster\_name](#output\_gke\_cluster\_name) | Name of the environment GKE Autopilot cluster, or null when disabled. |
| <a name="output_services"></a> [services](#output\_services) | Per-service golden-path facts: Cloud Run URL and name, image repository path, runtime and deploy SA emails, and (when a database is declared) the Cloud SQL connection name and IAM DB user. |
| <a name="output_workload_identity_pool_name"></a> [workload\_identity\_pool\_name](#output\_workload\_identity\_pool\_name) | Full resource name of the app-deploy Workload Identity pool, or null when enable\_app\_deploy\_wif = false. |
| <a name="output_workload_identity_provider"></a> [workload\_identity\_provider](#output\_workload\_identity\_provider) | Full resource name of the GitHub OIDC provider (the google-github-actions/auth `workload_identity_provider` input), or null until a service declares `github`. |
<!-- END_TF_DOCS -->
