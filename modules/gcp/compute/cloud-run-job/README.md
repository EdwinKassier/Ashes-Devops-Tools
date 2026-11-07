# cloud-run-job

Deploys a single [Cloud Run v2 job](https://cloud.google.com/run/docs/create-jobs):
a run-to-completion container (batch work, migrations, scheduled tasks) with no
request serving and no URL. It is the `runtime = "cloud-run-job"` option of the
`gcp/stages/app-services` golden path.

Secure by default:

- Runs as a **dedicated service account** (`service_account_email` is required).
- `deletion_protection` defaults to **on** via `enable_deletion_protection`.
- Secret env vars are sourced from **Secret Manager** (`value_source.secret_key_ref`),
  never passed as plaintext.
- Terraform owns the job configuration; the delivery pipeline owns the image
  (`template[0].template[0].containers[0].image` is ignored after creation).

The module creates no trigger. Start executions from CI (`gcloud run jobs execute`)
or a Cloud Scheduler job whose identity holds `roles/run.invoker` on the job.

<!-- BEGIN_TF_DOCS -->
Copyright 2026 Ashes

Cloud Run Job (v2) Module - Main Configuration

Deploys a single Cloud Run v2 job: a run-to-completion container (batch,
migration, scheduled task) with no request serving and no URL. Secure by
default: the job runs as a dedicated service account, secret environment
variables come from Secret Manager, and deletion protection is on. Executions
are started by a caller holding roles/run.invoker (or run.developer) on the
job, e.g. a CI pipeline or a Cloud Scheduler trigger; this module creates none.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |



## Resources

The following resources are created:


- resource.google_cloud_run_v2_job.this (modules/gcp/compute/cloud-run-job/main.tf#L14)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_image"></a> [image](#input\_image) | Fully qualified container image the job runs at creation (e.g. europe-west1-docker.pkg.dev/project/repo/job:tag). Later image changes are owned by the delivery pipeline and ignored by Terraform. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The GCP region for the Cloud Run job (e.g. europe-west1). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the Cloud Run job. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where the Cloud Run job is created. | `string` | n/a | yes |
| <a name="input_service_account_email"></a> [service\_account\_email](#input\_service\_account\_email) | Email of the dedicated runtime service account the job's tasks run as. Required: never run on the default compute SA. | `string` | n/a | yes |
| <a name="input_binary_authorization"></a> [binary\_authorization](#input\_binary\_authorization) | Optional Binary Authorization enforcement. Null (default) disables it. Set<br/>`{}` to enforce the project's default Binary Authorization policy, or set<br/>`policy` to the full name of a platform policy<br/>(projects/<p>/platforms/cloudRun/policies/<name>). `breakglass_justification`<br/>runs an image that violates the policy (audited); leave null normally. | <pre>object({<br/>    policy                   = optional(string)<br/>    breakglass_justification = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | CPU limit per task container (e.g. "1000m", "1", "2"). | `string` | `"1000m"` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Prevent accidental destruction of the Cloud Run job. Maps directly to the resource's deletion\_protection attribute. Defaults to true. | `bool` | `true` | no |
| <a name="input_env_vars"></a> [env\_vars](#input\_env\_vars) | Plain (non-secret) environment variables injected into the container as name => value. | `map(string)` | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the Cloud Run job. | `map(string)` | `{}` | no |
| <a name="input_max_retries"></a> [max\_retries](#input\_max\_retries) | Times a failed task is retried before the execution fails. | `number` | `3` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory limit per task container (e.g. "512Mi", "1Gi"). | `string` | `"512Mi"` | no |
| <a name="input_parallelism"></a> [parallelism](#input\_parallelism) | Maximum number of tasks running at once. Null lets Cloud Run run as many as possible. | `number` | `null` | no |
| <a name="input_secret_env_vars"></a> [secret\_env\_vars](#input\_secret\_env\_vars) | Environment variables sourced from Secret Manager. Each entry wires an env var<br/>to a secret version via value\_source.secret\_key\_ref; secret material is NEVER<br/>passed as plaintext here.<br/>  name    = env var name exposed to the container<br/>  secret  = Secret Manager secret id (short id or projects/<p>/secrets/<s>)<br/>  version = secret version ("latest" or a numeric version) | <pre>list(object({<br/>    name    = string<br/>    secret  = string<br/>    version = optional(string, "latest")<br/>  }))</pre> | `[]` | no |
| <a name="input_task_count"></a> [task\_count](#input\_task\_count) | Number of tasks each execution runs. | `number` | `1` | no |
| <a name="input_timeout"></a> [timeout](#input\_timeout) | Maximum duration of one task attempt, as a seconds string (e.g. "600s"). | `string` | `"600s"` | no |
| <a name="input_vpc_access"></a> [vpc\_access](#input\_vpc\_access) | Optional VPC egress configuration. Supply a connector for connector-based egress,<br/>or a network\_interfaces object for Direct VPC egress (not both). When null (the<br/>default) the job has no VPC egress.<br/>  connector = fully qualified VPC Access connector id (connector mode)<br/>  egress    = ALL\_TRAFFIC or PRIVATE\_RANGES\_ONLY<br/>  network\_interfaces = { network, subnetwork, tags } for Direct VPC egress | <pre>object({<br/>    connector = optional(string)<br/>    egress    = optional(string, "PRIVATE_RANGES_ONLY")<br/>    network_interfaces = optional(object({<br/>      network    = optional(string)<br/>      subnetwork = optional(string)<br/>      tags       = optional(list(string))<br/>    }))<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The fully qualified identifier of the Cloud Run job. |
| <a name="output_name"></a> [name](#output\_name) | The name of the Cloud Run job. |
| <a name="output_service_account_email"></a> [service\_account\_email](#output\_service\_account\_email) | The service account the job's tasks run as. |
<!-- END_TF_DOCS -->
