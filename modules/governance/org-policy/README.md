# Organization Policy Module

Applies organization policies (constraints) at org, folder, or project level.

## Features

- Boolean policies (enforce/deny)
- List policies (allowed/denied values)
- Folder and project-level policy overrides

## Usage

```hcl
module "org_policies" {
  source = "../../governance/org-policy"

  org_id = "123456789"

  boolean_policies = [
    {
      constraint = "compute.skipDefaultNetworkCreation"
      enforce    = true
    },
    {
      constraint = "iam.disableServiceAccountKeyCreation"
      enforce    = true
    }
  ]

  list_policies = [
    {
      constraint     = "compute.restrictVpcPeering"
      allowed_values = ["under:organizations/123456789"]
    },
    {
      constraint     = "gcp.resourceLocations"
      allowed_values = ["in:europe-locations"]
    }
  ]
}
```

## Common Policies

| Constraint | Type | Purpose |
|------------|------|---------|
| `compute.skipDefaultNetworkCreation` | Boolean | Prevent default VPC |
| `iam.disableServiceAccountKeyCreation` | Boolean | Enforce keyless auth |
| `compute.requireShieldedVm` | Boolean | Require Shielded VMs |
| `sql.restrictPublicIp` | Boolean | No public IPs on SQL |
| `compute.restrictVpcPeering` | List | Limit VPC peering scope |
| `gcp.resourceLocations` | List | Restrict deployment regions |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| org_id | Organization ID | string | yes |
| boolean_policies | List of boolean constraints | list(object) | no |
| list_policies | List of list constraints | list(object) | no |

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	parent = 
	
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
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |



## Resources

The following resources are created:


- resource.google_org_policy_custom_constraint.custom_constraints (modules/governance/org-policy/main.tf#L50)
- resource.google_org_policy_policy.boolean_policies (modules/governance/org-policy/main.tf#L8)
- resource.google_org_policy_policy.list_policies (modules/governance/org-policy/main.tf#L25)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_parent"></a> [parent](#input\_parent) | The parent resource where policies will be applied. Format: organizations/123, folders/456, or projects/789 | `string` | n/a | yes |
| <a name="input_boolean_policies"></a> [boolean\_policies](#input\_boolean\_policies) | List of boolean organization policies to enforce or disable | <pre>list(object({<br/>    constraint = string # e.g., "sql.restrictPublicIp", "compute.requireShieldedVm"<br/>    enforce    = bool   # true = enforce the constraint, false = disable it<br/>  }))</pre> | `[]` | no |
| <a name="input_custom_constraints"></a> [custom\_constraints](#input\_custom\_constraints) | List of custom organization policy constraints to create | <pre>list(object({<br/>    name           = string       # Unique name, e.g., "custom.disableGkeAutoUpgrade"<br/>    display_name   = string       # Human readable name<br/>    description    = string       # Description of the constraint<br/>    action_type    = string       # ALLOW or DENY<br/>    condition      = string       # CEL condition, e.g., "resource.management.autoUpgrade == true"<br/>    method_types   = list(string) # Operations to restrict: CREATE, UPDATE, DELETE<br/>    resource_types = list(string) # Resources to restrict: e.g. ["container.googleapis.com/NodePool"]<br/>  }))</pre> | `[]` | no |
| <a name="input_list_policies"></a> [list\_policies](#input\_list\_policies) | List of list-type organization policies with allowed/denied values | <pre>list(object({<br/>    constraint     = string       # e.g., "gcp.resourceLocations"<br/>    allow_all      = bool         # Allow all values (overrides allowed_values)<br/>    deny_all       = bool         # Deny all values (overrides denied_values)<br/>    allowed_values = list(string) # Specific values to allow<br/>    denied_values  = list(string) # Specific values to deny<br/>  }))</pre> | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply for tracking and organization | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_boolean_policy_names"></a> [boolean\_policy\_names](#output\_boolean\_policy\_names) | Map of boolean policy constraint names to their full resource names |
| <a name="output_custom_constraints"></a> [custom\_constraints](#output\_custom\_constraints) | Map of created custom constraints |
| <a name="output_disabled_boolean_policies"></a> [disabled\_boolean\_policies](#output\_disabled\_boolean\_policies) | List of boolean policies that are disabled (enforce = false) |
| <a name="output_enforced_boolean_policies"></a> [enforced\_boolean\_policies](#output\_enforced\_boolean\_policies) | List of boolean policies that are enforced (enforce = true) |
| <a name="output_list_policy_names"></a> [list\_policy\_names](#output\_list\_policy\_names) | Map of list policy constraint names to their full resource names |
| <a name="output_parent"></a> [parent](#output\_parent) | The parent resource where policies are applied |
<!-- END_TF_DOCS -->