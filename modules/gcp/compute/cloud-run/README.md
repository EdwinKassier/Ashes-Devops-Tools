# cloud-run

Deploys a single [Cloud Run v2](https://cloud.google.com/run) service — the serverless
application runtime for this landing zone.

Secure by default:

- Runs as a **dedicated service account** (`service_account_email` is required).
- Ingress defaults to `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` — not public.
- Private unless `enable_unauthenticated = true` grants `roles/run.invoker` to `allUsers`.
- `deletion_protection` defaults to **on** via `enable_deletion_protection`.
- Secret env vars are sourced from **Secret Manager** (`value_source.secret_key_ref`),
  never passed as plaintext.

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Cloud Run (v2) Module - Main Configuration

Deploys a single Cloud Run v2 service — the serverless application runtime.
Secure by default: the service runs as a dedicated service account, is reachable
only via an internal load balancer, and stays private unless unauthenticated
access is explicitly enabled. Secret environment variables are sourced from
Secret Manager, never passed as plaintext.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	image =
	location =
	name =
	project_id =
	service_account_email =
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



## Resources

The following resources are created:


- resource.google_cloud_run_v2_service.this (modules/gcp/compute/cloud-run/main.tf#L13)
- resource.google_cloud_run_v2_service_iam_member.unauthenticated (modules/gcp/compute/cloud-run/main.tf#L111)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_image"></a> [image](#input\_image) | Fully qualified container image to deploy at creation (e.g. europe-west1-docker.pkg.dev/project/repo/app:tag). Later image changes are owned by the delivery pipeline and ignored by Terraform. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The GCP region for the Cloud Run service (e.g. europe-west1). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the Cloud Run service. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where the Cloud Run service is created. | `string` | n/a | yes |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Email of the dedicated runtime service account the service runs as. Required — never run on the default compute SA. | `string` | n/a | yes |
| <a name="input_binary_authorization"></a> [binary\_authorization](#input\_binary\_authorization) | Optional Binary Authorization enforcement. Null (default) disables it. Set<br/>`{}` to enforce the project's default Binary Authorization policy, or set<br/>`policy` to the full name of a platform policy<br/>(projects/<p>/platforms/cloudRun/policies/<name>). `breakglass_justification`<br/>deploys an image that violates the policy (audited) — leave null normally. | <pre>object({<br/>    policy                   = optional(string)<br/>    breakglass_justification = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_concurrency"></a> [concurrency](#input\_concurrency) | Maximum number of concurrent requests per instance (max\_instance\_request\_concurrency). | `number` | `80` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | CPU limit per container instance (e.g. "1000m", "1", "2"). | `string` | `"1000m"` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Prevent accidental destruction of the Cloud Run service. Maps directly to the<br/>resource's deletion\_protection attribute. Defaults to true; set to false to allow<br/>`terraform destroy` to remove the service. | `bool` | `true` | no |
| <a name="input_enable_unauthenticated"></a> [enable\_unauthenticated](#input\_enable\_unauthenticated) | When true, grants roles/run.invoker to allUsers, making the service publicly<br/>invokable without authentication. Defaults to false — the service is private and<br/>only callable by principals with an explicit invoker binding. | `bool` | `false` | no |
| <a name="input_env_vars"></a> [env\_vars](#input\_env\_vars) | Plain (non-secret) environment variables injected into the container as name => value. | `map(string)` | `{}` | no |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | Ingress traffic policy. Defaults to INGRESS\_TRAFFIC\_INTERNAL\_LOAD\_BALANCER so the<br/>service is reachable only via an internal HTTP(S) load balancer (not the public<br/>internet). Set to INGRESS\_TRAFFIC\_ALL only for deliberately public services. | `string` | `"INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the Cloud Run service. | `map(string)` | `{}` | no |
| <a name="input_max_instance_count"></a> [max\_instance\_count](#input\_max\_instance\_count) | Maximum number of instances. | `number` | `100` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory limit per container instance (e.g. "512Mi", "1Gi"). | `string` | `"512Mi"` | no |
| <a name="input_min_instance_count"></a> [min\_instance\_count](#input\_min\_instance\_count) | Minimum number of instances (0 allows scale-to-zero). | `number` | `0` | no |
| <a name="input_secret_env_vars"></a> [secret\_env\_vars](#input\_secret\_env\_vars) | Environment variables sourced from Secret Manager. Each entry wires an env var<br/>to a secret version via value\_source.secret\_key\_ref — secret material is NEVER<br/>passed as plaintext here.<br/>  name    = env var name exposed to the container<br/>  secret  = Secret Manager secret id (short id or projects/<p>/secrets/<s>)<br/>  version = secret version ("latest" or a numeric version) | <pre>list(object({<br/>    name    = string<br/>    secret  = string<br/>    version = optional(string, "latest")<br/>  }))</pre> | `[]` | no |
| <a name="input_timeout"></a> [timeout](#input\_timeout) | Maximum request duration, as a duration string (e.g. "300s"). | `string` | `"300s"` | no |
| <a name="input_vpc_access"></a> [vpc\_access](#input\_vpc\_access) | Optional VPC egress configuration. Supply a connector for connector-based egress,<br/>or a network\_interfaces object for Direct VPC egress (not both). When null (the<br/>default) the service has no VPC egress.<br/>  connector = fully qualified VPC Access connector id (connector mode)<br/>  egress    = ALL\_TRAFFIC or PRIVATE\_RANGES\_ONLY<br/>  network\_interfaces = { network, subnetwork, tags } for Direct VPC egress | <pre>object({<br/>    connector = optional(string)<br/>    egress    = optional(string, "PRIVATE_RANGES_ONLY")<br/>    network_interfaces = optional(object({<br/>      network    = optional(string)<br/>      subnetwork = optional(string)<br/>      tags       = optional(list(string))<br/>    }))<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The fully qualified identifier of the Cloud Run service. |
| <a name="output_ingress"></a> [ingress](#output\_ingress) | The ingress traffic policy applied to the service. |
| <a name="output_latest_ready_revision"></a> [latest\_ready\_revision](#output\_latest\_ready\_revision) | The name of the latest revision that is serving ready traffic. |
| <a name="output_name"></a> [name](#output\_name) | The name of the Cloud Run service. |
| <a name="output_uri"></a> [uri](#output\_uri) | The main URI at which the Cloud Run service is reachable. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "api" {
  source = "../../modules/gcp/compute/cloud-run"

  project_id            = "my-project-id"
  location              = "europe-west1"
  name                  = "my-api"
  image                 = "europe-west1-docker.pkg.dev/my-project-id/apps/api:1.0.0"
  service_account_email = "my-api-run@my-project-id.iam.gserviceaccount.com"

  env_vars = {
    LOG_LEVEL = "info"
  }

  secret_env_vars = [
    {
      name    = "DATABASE_URL"
      secret  = "database-url"
      version = "latest"
    },
  ]
}
```
