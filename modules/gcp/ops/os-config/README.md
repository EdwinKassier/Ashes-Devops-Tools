# Google Cloud VM Manager (OS Config) Module

Scheduled OS patch deployments via
[VM Manager / OS Config](https://docs.cloud.google.com/compute/docs/os-patch-management) —
the GCP parity counterpart to AWS `modules/aws/ops/systems-manager` (patch
baselines / Maintenance Windows). Each entry is a recurring weekly patch job
targeting all instances in the project, or a label-selected subset.

## Usage

```hcl
module "os_config" {
  source = "../../ops/os-config"

  project_id = "my-project"

  patch_deployments = {
    weekly-all = {
      all_instances = true
      reboot_config = "DEFAULT"
      day_of_week   = "SUNDAY"
      start_time    = "03:00"
      time_zone     = "Europe/London"
    }
    db-tier = {
      all_instances   = false
      instance_labels = { tier = "database" }
      reboot_config   = "NEVER"
      day_of_week     = "SATURDAY"
      start_time      = "02:00"
    }
  }
}
```

> VM Manager must be enabled on the project (the `osconfig.googleapis.com` API
> and the OS Config agent on the VMs) for patch deployments to execute.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |



## Resources

The following resources are created:


- resource.google_os_config_patch_deployment.this (modules/gcp/ops/os-config/main.tf#L13)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID where the OS Config (VM Manager) patch deployments are created. | `string` | n/a | yes |
| <a name="input_patch_deployments"></a> [patch\_deployments](#input\_patch\_deployments) | VM Manager scheduled OS patch deployments, keyed by deployment id — the GCP<br/>parity counterpart to AWS Systems Manager patch baselines/Maintenance Windows.<br/>Each runs a recurring weekly patch job against the matched instances.<br/>  - all\_instances:  when true, patch every VM in the project (default true)<br/>  - instance\_labels: label map to target a subset (used when all\_instances = false)<br/>  - reboot\_config:   DEFAULT \| ALWAYS \| NEVER<br/>  - day\_of\_week + start HH:MM + time\_zone: the recurring weekly window | <pre>map(object({<br/>    all_instances   = optional(bool, true)<br/>    instance_labels = optional(map(string), {})<br/>    reboot_config   = optional(string, "DEFAULT")<br/>    day_of_week     = optional(string, "SUNDAY")<br/>    start_time      = optional(string, "03:00")<br/>    time_zone       = optional(string, "Etc/UTC")<br/>    description     = optional(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_patch_deployment_ids"></a> [patch\_deployment\_ids](#output\_patch\_deployment\_ids) | Map of deployment key to the created patch deployment resource ID. |
| <a name="output_patch_deployment_names"></a> [patch\_deployment\_names](#output\_patch\_deployment\_names) | Map of deployment key to the fully-qualified patch deployment name. |
<!-- END_TF_DOCS -->
