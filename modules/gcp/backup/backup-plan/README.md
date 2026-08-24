# Google Cloud Backup Plan Module

Scheduled, retained persistent-disk snapshots via
[`google_compute_resource_policy`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_resource_policy)
snapshot-schedule policies — the GCP parity counterpart to the AWS
`modules/aws/backup/*` (backup-vault + backup-org-policy). Where AWS centralizes
scheduled backups and retention in a WORM vault, GCP expresses the same
"scheduled backups with a retention policy" capability as regional resource
policies you attach to disks.

Each entry in `var.schedules` becomes one resource policy. A schedule may set at
most one cadence (`daily_schedule`, `weekly_schedule`, or `hourly_schedule`);
when none is given, a secure default daily schedule (04:00, once per day) is
applied. Attach the resulting policies to disks with
`google_compute_disk_resource_policy_attachment` (out of module scope, per-disk).

## Usage

```hcl
module "backup" {
  source = "../../backup/backup-plan"

  project_id = "my-project"
  region     = "europe-west1"

  schedules = {
    daily-30d = {
      daily_schedule   = { start_time = "04:00", days_in_cycle = 1 }
      retention_policy = { max_retention_days = 30, on_source_disk_delete = "APPLY_RETENTION_POLICY" }
    }
    weekly-1y = {
      weekly_schedule  = { day_of_weeks = [{ day = "SUNDAY", start_time = "02:00" }] }
      retention_policy = { max_retention_days = 365 }
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
Backup Plan Module - Scheduled Persistent Disk Snapshots

GCP parity counterpart to the AWS backup modules (backup-vault + backup-org-policy).
Where AWS centralizes scheduled backups + retention in a WORM vault, GCP expresses
the same "scheduled backups with a retention policy" capability through
google\_compute\_resource\_policy snapshot-schedule policies. Attach the resulting
policies to persistent disks to get automatic, retained snapshots.

Each entry in var.schedules becomes one resource policy. A schedule may specify
exactly one of daily / weekly / hourly cadence; when none is given the module
falls back to a secure default daily schedule.

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


- resource.google_compute_resource_policy.snapshot (modules/gcp/backup/backup-plan/main.tf#L32)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID where the snapshot-schedule resource policies will be created (6-30 characters, lowercase alphanumeric and hyphens). | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to snapshots created by every schedule. Merged with each schedule's own snapshot\_properties.labels. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | Region where the snapshot-schedule resource policies are created. Resource policies are regional and can only be attached to disks in the same region. | `string` | `"europe-west1"` | no |
| <a name="input_schedules"></a> [schedules](#input\_schedules) | Map of snapshot-schedule policies to create. The map key is the resource policy name.<br/>Each entry may specify at most one cadence (daily\_schedule, weekly\_schedule, or<br/>hourly\_schedule); when none is given a secure default daily schedule (04:00, once per<br/>day) is applied. retention\_policy and snapshot\_properties fall back to secure defaults. | <pre>map(object({<br/>    daily_schedule = optional(object({<br/>      days_in_cycle = optional(number, 1)<br/>      start_time    = optional(string, "04:00")<br/>    }))<br/>    weekly_schedule = optional(object({<br/>      day_of_weeks = list(object({<br/>        day        = string<br/>        start_time = string<br/>      }))<br/>    }))<br/>    hourly_schedule = optional(object({<br/>      hours_in_cycle = number<br/>      start_time     = string<br/>    }))<br/>    retention_policy = optional(object({<br/>      max_retention_days    = optional(number, 30)<br/>      on_source_disk_delete = optional(string, "KEEP_AUTO_SNAPSHOTS")<br/>    }), {})<br/>    snapshot_properties = optional(object({<br/>      labels            = optional(map(string), {})<br/>      storage_locations = optional(list(string))<br/>      guest_flush       = optional(bool, false)<br/>    }), {})<br/>  }))</pre> | <pre>{<br/>  "daily": {<br/>    "daily_schedule": {<br/>      "days_in_cycle": 1,<br/>      "start_time": "04:00"<br/>    },<br/>    "retention_policy": {<br/>      "max_retention_days": 30<br/>    }<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_resource_policy_ids"></a> [resource\_policy\_ids](#output\_resource\_policy\_ids) | Map of schedule name to the resource policy ID. |
| <a name="output_resource_policy_self_links"></a> [resource\_policy\_self\_links](#output\_resource\_policy\_self\_links) | Map of schedule name to the resource policy self\_link (full resource URL). Attach these to persistent disks via google\_compute\_disk\_resource\_policy\_attachment. |
| <a name="output_schedule_names"></a> [schedule\_names](#output\_schedule\_names) | List of the snapshot-schedule policy names created by this module. |
<!-- END_TF_DOCS -->
