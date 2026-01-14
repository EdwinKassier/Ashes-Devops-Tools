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
