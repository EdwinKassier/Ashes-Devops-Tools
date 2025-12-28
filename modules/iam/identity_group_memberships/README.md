# Google Cloud Identity Group Memberships Module

This Terraform module manages memberships in Google Cloud Identity groups.

## Overview

This module adds members to Cloud Identity groups created by the `identity_group` module. It supports assigning different roles within the group (MEMBER, MANAGER, OWNER).

## Usage

### Basic Membership

```hcl
module "team_memberships" {
  source = "./modules/iam/identity_group_memberships"

  members = [
    {
      group_id  = "groups/abc123"  # Group resource name
      member_id = "user@example.com"
      roles     = ["MEMBER"]
    }
  ]
}
```

### Multiple Members with Different Roles

```hcl
module "dev_team_members" {
  source = "./modules/iam/identity_group_memberships"

  members = [
    # Regular team members
    {
      group_id  = module.identity_groups.identity_groups["dev-team"].name
      member_id = "developer1@example.com"
      roles     = ["MEMBER"]
    },
    {
      group_id  = module.identity_groups.identity_groups["dev-team"].name
      member_id = "developer2@example.com"
      roles     = ["MEMBER"]
    },
    # Team lead with manager privileges
    {
      group_id  = module.identity_groups.identity_groups["dev-team"].name
      member_id = "team-lead@example.com"
      roles     = ["MEMBER", "MANAGER"]
    },
    # Group owner (can delete group)
    {
      group_id  = module.identity_groups.identity_groups["dev-team"].name
      member_id = "director@example.com"
      roles     = ["MEMBER", "OWNER"]
    }
  ]
}
```

### Adding a Group as Member of Another Group (Nested Groups)

```hcl
module "nested_membership" {
  source = "./modules/iam/identity_group_memberships"

  members = [
    {
      group_id  = module.identity_groups.identity_groups["all-engineers"].name
      member_id = "dev-team@example.com"  # Another group's email
      roles     = ["MEMBER"]
    }
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| members | List of group membership configurations | list(object) | [] | no |

### members Object

| Attribute | Description | Type | Required |
|-----------|-------------|------|:--------:|
| group_id | The resource name of the group | string | yes |
| member_id | Email address of the member | string | yes |
| roles | List of roles: MEMBER, MANAGER, OWNER | list(string) | yes |

## Outputs

| Name | Description |
|------|-------------|
| memberships | Map of created group memberships with their details |

## Role Types

| Role | Description |
|------|-------------|
| `MEMBER` | Basic membership, can access resources the group has access to |
| `MANAGER` | Can add/remove members and edit group settings |
| `OWNER` | Full control including ability to delete the group |

## Best Practices

1. **OWNER role**: Only assign to trusted administrators
2. **MANAGER role**: Limit to team leads who need to manage membership
3. **Avoid direct user access**: Add users to groups, not directly to resources
4. **Document membership**: Keep track of why each member was added
5. **Regular cleanup**: Remove members who no longer need access

## Security Considerations

> [!CAUTION]
> The OWNER role allows deletion of the entire group, which would remove all associated IAM permissions. Use sparingly.

## Related Modules

- `identity_group` - Create the groups before adding memberships
- `organisation` - Uses this module for environment-specific group memberships
