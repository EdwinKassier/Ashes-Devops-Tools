# Google Cloud Identity Group Module

This Terraform module creates and manages Google Cloud Identity groups.

## Overview

Cloud Identity groups provide a way to manage access to GCP resources by grouping users together. Instead of granting IAM roles to individual users, you can grant roles to groups, simplifying access management.

## Usage

### Basic Identity Group

```hcl
module "dev_team" {
  source = "./modules/iam/identity_group"

  customer_id = "C0abc123"  # Your Cloud Identity customer ID

  identity_groups = [
    {
      id           = "dev-team"
      display_name = "Development Team"
      email        = "dev-team@example.com"
      description  = "All members of the development team"
    }
  ]
}
```

### Multiple Groups

```hcl
module "teams" {
  source = "./modules/iam/identity_group"

  customer_id = "C0abc123"

  identity_groups = [
    {
      id           = "platform-team"
      display_name = "Platform Team"
      email        = "platform@example.com"
      description  = "Platform engineering team"
    },
    {
      id           = "security-team"
      display_name = "Security Team"
      email        = "security@example.com"
      description  = "Security operations team"
    },
    {
      id           = "data-team"
      display_name = "Data Team"
      email        = "data@example.com"
      description  = "Data engineering team"
    }
  ]
}
```

### With Custom Labels

```hcl
module "labeled_group" {
  source = "./modules/iam/identity_group"

  customer_id = "C0abc123"

  identity_groups = [
    {
      id           = "contractors"
      display_name = "External Contractors"
      email        = "contractors@example.com"
      description  = "External contractor access group"
      labels = {
        "cloudidentity.googleapis.com/groups.security" = "external"
      }
    }
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| customer_id | Cloud Identity customer ID (e.g., 'C0abc123') | string | - | yes |
| identity_groups | List of identity groups to create | list(object) | [] | no |

### identity_groups Object

| Attribute | Description | Type | Required |
|-----------|-------------|------|:--------:|
| id | Unique identifier for the group | string | yes |
| display_name | Human-readable name | string | yes |
| email | Group email address | string | yes |
| description | Group description | string | no |
| initial_group_config | Initial config: WITH_INITIAL_OWNER or EMPTY | string | no |
| labels | Additional labels | map(string) | no |

## Outputs

| Name | Description |
|------|-------------|
| identity_groups | Map of created identity groups with their details |

## Finding Your Customer ID

You can find your Cloud Identity customer ID:

1. **Admin Console**: admin.google.com > Account > Account Settings
2. **gcloud CLI**: `gcloud organizations list` (shows directory_customer_id)
3. **API**: Cloud Identity API `customers` endpoint

## Best Practices

1. **Use groups over individual users**: Always grant IAM roles to groups, not individuals
2. **Meaningful names**: Use descriptive names that indicate the group's purpose
3. **Consistent naming**: Follow a naming convention (e.g., `gcp-{team}-{role}@domain.com`)
4. **Nested groups**: Consider using nested groups for complex hierarchies
5. **Regular audits**: Periodically review group memberships

## Related Modules

- `identity_group_memberships` - Add members to groups created by this module
- `organisation` - Uses this module to create environment-specific groups
