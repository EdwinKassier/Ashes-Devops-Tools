# Security Command Center (SCC) Notifications Module

Creates Security Command Center notification configurations with Pub/Sub topics.

## Features

- Single or multiple notification configs
- Severity-based routing (critical → PagerDuty, medium → email)
- Automatic IAM binding for SCC service account

## Usage

### Single Config (Legacy)
```hcl
module "scc_notifications" {
  source = "../../governance/scc"

  org_id     = "123456789"
  project_id = "my-admin-project"
  filter     = "state=\"ACTIVE\""
}
```

### Multiple Configs (Severity Routing)
```hcl
module "scc_notifications" {
  source = "../../governance/scc"

  org_id     = "123456789"
  project_id = "my-admin-project"

  notification_configs = {
    "critical-high" = {
      pubsub_topic_name = "scc-critical-findings"
      description       = "Critical and High severity"
      filter            = "state=\"ACTIVE\" AND (severity=\"CRITICAL\" OR severity=\"HIGH\")"
    }
    "medium-low" = {
      pubsub_topic_name = "scc-medium-findings"
      description       = "Medium and Low severity"
      filter            = "state=\"ACTIVE\" AND (severity=\"MEDIUM\" OR severity=\"LOW\")"
    }
  }
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| org_id | Organization ID | string | yes |
| project_id | Project for Pub/Sub topics | string | yes |
| notification_configs | Map of notification configs | map(object) | no |

## Outputs

| Name | Description |
|------|-------------|
| topics | Map of created Pub/Sub topics |
| notification_configs | Map of SCC notification configs |

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	org_id =
	project_id =
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



## Resources

The following resources are created:


- resource.google_pubsub_topic.scc_notifications (modules/gcp/governance/scc/main.tf#L38)
- resource.google_pubsub_topic.scc_notifications_multi (modules/gcp/governance/scc/main.tf#L72)
- resource.google_pubsub_topic_iam_member.scc_publisher (modules/gcp/governance/scc/main.tf#L59)
- resource.google_pubsub_topic_iam_member.scc_publisher_multi (modules/gcp/governance/scc/main.tf#L100)
- resource.google_pubsub_topic_iam_member.scc_publisher_v2 (modules/gcp/governance/scc/main.tf#L128)
- resource.google_scc_mute_config.this (modules/gcp/governance/scc/main.tf#L141)
- resource.google_scc_notification_config.notification_config (modules/gcp/governance/scc/main.tf#L46)
- resource.google_scc_notification_config.notification_config_multi (modules/gcp/governance/scc/main.tf#L86)
- resource.google_scc_v2_organization_mute_config.this (modules/gcp/governance/scc/main.tf#L151)
- resource.google_scc_v2_organization_notification_config.this (modules/gcp/governance/scc/main.tf#L113)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Numeric GCP Organization ID where SCC is enabled (digits only, without 'organizations/' prefix). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where the Pub/Sub topic will be created (lowercase letters, digits, hyphens; 6–30 characters; starts with a letter). | `string` | n/a | yes |
| <a name="input_config_id"></a> [config\_id](#input\_config\_id) | ID for the notification config (legacy single config) | `string` | `"scc-notification-config"` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the notification config (legacy single config) | `string` | `"SCC notifications for active findings"` | no |
| <a name="input_filter"></a> [filter](#input\_filter) | The filter string to trigger notifications (legacy single config) | `string` | `"state=\"ACTIVE\""` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Optional customer-managed KMS key used to encrypt SCC notification topics | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource this module creates (merged with the provider default\_labels; resource-specific labels win). | `map(string)` | `{}` | no |
| <a name="input_mute_configs"></a> [mute\_configs](#input\_mute\_configs) | Map of SCC mute configs keyed by mute\_config\_id (created with the API generation(s) selected by scc\_api\_version). type is STATIC or DYNAMIC. | <pre>map(object({<br/>    description = optional(string, "Managed by Terraform")<br/>    filter      = string<br/>    type        = optional(string, "STATIC")<br/>  }))</pre> | `{}` | no |
| <a name="input_notification_configs"></a> [notification\_configs](#input\_notification\_configs) | Map of notification configurations for severity-based routing.<br/>When provided, this takes precedence over the legacy single config variables.<br/><br/>Example:<br/>notification\_configs = {<br/>  "critical-high" = {<br/>    pubsub\_topic\_name = "scc-critical-findings"<br/>    description       = "Critical and High severity findings"<br/>    filter            = "state=\"ACTIVE\" AND (severity=\"CRITICAL\" OR severity=\"HIGH\")"<br/>  }<br/>  "medium-low" = {<br/>    pubsub\_topic\_name = "scc-medium-findings"<br/>    description       = "Medium and Low severity findings"<br/>    filter            = "state=\"ACTIVE\" AND (severity=\"MEDIUM\" OR severity=\"LOW\")"<br/>  }<br/>} | <pre>map(object({<br/>    pubsub_topic_name = string<br/>    description       = optional(string, "SCC notification configuration")<br/>    filter            = string<br/>  }))</pre> | `{}` | no |
| <a name="input_pubsub_topic_name"></a> [pubsub\_topic\_name](#input\_pubsub\_topic\_name) | Name of the Pub/Sub topic for SCC notifications (legacy single config) | `string` | `"scc-notifications"` | no |
| <a name="input_scc_api_version"></a> [scc\_api\_version](#input\_scc\_api\_version) | SCC API generation for notification and mute configs: v1 (default, unchanged), both (create the v2 twins next to v1 to verify), or v2 (flip; the v1 configs are destroyed). v1 and v2 cannot see each other's configs; see docs/runbooks/scc-v2-migration.md. | `string` | `"v1"` | no |
| <a name="input_scc_location"></a> [scc\_location](#input\_scc\_location) | Location of the SCC v2 configs (global or a data-residency region). Ignored for v1. | `string` | `"global"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_mute_config_names"></a> [mute\_config\_names](#output\_mute\_config\_names) | Resource names of the mute configs (v1 and/or v2 per scc\_api\_version) |
| <a name="output_notification_config_name"></a> [notification\_config\_name](#output\_notification\_config\_name) | The resource name of the notification config (legacy single config) |
| <a name="output_notification_configs"></a> [notification\_configs](#output\_notification\_configs) | Map of SCC notification configurations for severity-based routing |
| <a name="output_topic_id"></a> [topic\_id](#output\_topic\_id) | The ID of the created Pub/Sub topic (legacy single config) |
| <a name="output_topic_name"></a> [topic\_name](#output\_topic\_name) | The name of the created Pub/Sub topic (legacy single config) |
| <a name="output_topics"></a> [topics](#output\_topics) | Map of Pub/Sub topics created for severity-based routing |
| <a name="output_v2_notification_configs"></a> [v2\_notification\_configs](#output\_v2\_notification\_configs) | Map of SCC v2 notification configs (empty unless scc\_api\_version is both or v2) |
<!-- END_TF_DOCS -->
