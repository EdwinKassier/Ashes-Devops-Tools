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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |



## Resources

The following resources are created:


- resource.google_pubsub_topic.scc_notifications (modules/governance/scc/main.tf#L5)
- resource.google_pubsub_topic.scc_notifications_multi (modules/governance/scc/main.tf#L37)
- resource.google_pubsub_topic_iam_member.scc_publisher (modules/governance/scc/main.tf#L25)
- resource.google_pubsub_topic_iam_member.scc_publisher_multi (modules/governance/scc/main.tf#L65)
- resource.google_scc_notification_config.notification_config (modules/governance/scc/main.tf#L12)
- resource.google_scc_notification_config.notification_config_multi (modules/governance/scc/main.tf#L51)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The organization ID where SCC is enabled | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID where the Pub/Sub topic will be created | `string` | n/a | yes |
| <a name="input_config_id"></a> [config\_id](#input\_config\_id) | ID for the notification config (legacy single config) | `string` | `"scc-notification-config"` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the notification config (legacy single config) | `string` | `"SCC notifications for active findings"` | no |
| <a name="input_filter"></a> [filter](#input\_filter) | The filter string to trigger notifications (legacy single config) | `string` | `"state=\"ACTIVE\""` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Optional customer-managed KMS key used to encrypt SCC notification topics | `string` | `null` | no |
| <a name="input_notification_configs"></a> [notification\_configs](#input\_notification\_configs) | Map of notification configurations for severity-based routing.<br/>When provided, this takes precedence over the legacy single config variables.<br/><br/>Example:<br/>notification\_configs = {<br/>  "critical-high" = {<br/>    pubsub\_topic\_name = "scc-critical-findings"<br/>    description       = "Critical and High severity findings"<br/>    filter            = "state=\"ACTIVE\" AND (severity=\"CRITICAL\" OR severity=\"HIGH\")"<br/>  }<br/>  "medium-low" = {<br/>    pubsub\_topic\_name = "scc-medium-findings"<br/>    description       = "Medium and Low severity findings"<br/>    filter            = "state=\"ACTIVE\" AND (severity=\"MEDIUM\" OR severity=\"LOW\")"<br/>  }<br/>} | <pre>map(object({<br/>    pubsub_topic_name = string<br/>    description       = optional(string, "SCC notification configuration")<br/>    filter            = string<br/>  }))</pre> | `{}` | no |
| <a name="input_pubsub_topic_name"></a> [pubsub\_topic\_name](#input\_pubsub\_topic\_name) | Name of the Pub/Sub topic for SCC notifications (legacy single config) | `string` | `"scc-notifications"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_notification_config_name"></a> [notification\_config\_name](#output\_notification\_config\_name) | The resource name of the notification config (legacy single config) |
| <a name="output_notification_configs"></a> [notification\_configs](#output\_notification\_configs) | Map of SCC notification configurations for severity-based routing |
| <a name="output_topic_id"></a> [topic\_id](#output\_topic\_id) | The ID of the created Pub/Sub topic (legacy single config) |
| <a name="output_topic_name"></a> [topic\_name](#output\_topic\_name) | The name of the created Pub/Sub topic (legacy single config) |
| <a name="output_topics"></a> [topics](#output\_topics) | Map of Pub/Sub topics created for severity-based routing |
<!-- END_TF_DOCS -->