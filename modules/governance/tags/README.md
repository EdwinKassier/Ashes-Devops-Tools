# Resource Tags Module

Manages Tag Keys and Values at the organization level for fine-grained access control and cost tracking.

## Features

- Create Tag Keys
- Create Tag Values
- Centralized tag management

## Usage

```hcl
module "tags" {
  source = "../../governance/tags"

  org_id = "123456789"

  tags = {
    "environment" = {
      description = "Deployment environment"
      values = {
        "dev"  = "Development"
        "uat"  = "User Acceptance Testing"
        "prod" = "Production"
      }
    }
    "cost-center" = {
      description = "Department for billing"
      values = {
        "engineering" = "Engineering Dept"
        "marketing"   = "Marketing Dept"
      }
    }
  }
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| org_id | Organization ID | string | yes |
| tags | Map of tag keys and their values | map(object) | yes |

## Outputs

| Name | Description |
|------|-------------|
| tag_keys | Map of tag key names to IDs |
| tag_values | Map of tag value names to IDs |
