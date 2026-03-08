# Hierarchical Firewall Policy Module

Creates organizational or folder-level firewall policies that apply across multiple projects in a hierarchical manner.

## Features

- Create firewall policies at organization or folder level
- Define ingress and egress rules with flexible matching
- Support for threat intelligence and geo-blocking
- Attach policies to multiple folders/organizations
- Full logging support

## Usage

```hcl
module "org_firewall_policy" {
  source = "../network/hierarchical-firewall"

  parent      = "organizations/123456789"
  policy_name = "org-security-policy"
  description = "Organization-wide security baseline"

  rules = [
    {
      priority    = 1000
      action      = "deny"
      direction   = "INGRESS"
      description = "Block traffic from sanctioned countries"
      layer4_configs = [{ ip_protocol = "all" }]
      src_region_codes = ["KP", "IR", "SY"]
    },
    {
      priority    = 2000
      action      = "allow"
      direction   = "INGRESS"
      description = "Allow SSH from corporate IP ranges"
      layer4_configs = [{ ip_protocol = "tcp", ports = ["22"] }]
      src_ip_ranges = ["10.0.0.0/8", "172.16.0.0/12"]
    }
  ]

  associations = [
    "organizations/123456789"
  ]
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| parent | Organization or folder ID | string | yes |
| policy_name | Short name for the policy | string | yes |
| rules | List of firewall rules | list(object) | no |
| associations | Resources to attach policy to | list(string) | no |
| enable_logging | Default logging for rules | bool | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the firewall policy |
| self_link | The self_link of the policy |
| rules | Map of created rules |
| associations | Map of policy associations |

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Hierarchical Firewall Policy Module - Main Configuration

Creates organizational or folder-level firewall policies that apply
across multiple projects in a hierarchical manner.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	parent = 
	policy_name = 
	
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


- resource.google_compute_firewall_policy.policy (modules/network/hierarchical-firewall/main.tf#L14)
- resource.google_compute_firewall_policy_association.associations (modules/network/hierarchical-firewall/main.tf#L70)
- resource.google_compute_firewall_policy_rule.rules (modules/network/hierarchical-firewall/main.tf#L24)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_parent"></a> [parent](#input\_parent) | The parent organization or folder (e.g., 'organizations/123456789' or 'folders/123456789') | `string` | n/a | yes |
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | Short name for the hierarchical firewall policy | `string` | n/a | yes |
| <a name="input_associations"></a> [associations](#input\_associations) | List of folder or organization resource IDs to attach this policy to | `list(string)` | `[]` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the firewall policy | `string` | `"Managed by Terraform"` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Default logging setting for rules (can be overridden per rule) | `bool` | `true` | no |
| <a name="input_rules"></a> [rules](#input\_rules) | List of firewall policy rules | <pre>list(object({<br/>    priority       = number<br/>    action         = string # "allow", "deny", "goto_next"<br/>    direction      = string # "INGRESS" or "EGRESS"<br/>    description    = optional(string)<br/>    disabled       = optional(bool, false)<br/>    enable_logging = optional(bool, false)<br/><br/>    layer4_configs = list(object({<br/>      ip_protocol = string<br/>      ports       = optional(list(string))<br/>    }))<br/><br/>    # Source filters (for INGRESS)<br/>    src_ip_ranges            = optional(list(string))<br/>    src_fqdns                = optional(list(string))<br/>    src_region_codes         = optional(list(string))<br/>    src_threat_intelligences = optional(list(string))<br/><br/>    # Destination filters (for EGRESS)<br/>    dest_ip_ranges            = optional(list(string))<br/>    dest_fqdns                = optional(list(string))<br/>    dest_region_codes         = optional(list(string))<br/>    dest_threat_intelligences = optional(list(string))<br/><br/>    # Targets<br/>    target_networks         = optional(list(string))<br/>    target_service_accounts = optional(list(string))<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_associations"></a> [associations](#output\_associations) | Map of created policy associations |
| <a name="output_fingerprint"></a> [fingerprint](#output\_fingerprint) | Fingerprint of the firewall policy |
| <a name="output_id"></a> [id](#output\_id) | The ID of the hierarchical firewall policy |
| <a name="output_name"></a> [name](#output\_name) | The name of the hierarchical firewall policy |
| <a name="output_policy"></a> [policy](#output\_policy) | The full firewall policy resource |
| <a name="output_rule_tuple_count"></a> [rule\_tuple\_count](#output\_rule\_tuple\_count) | Total count of rule tuples in this policy |
| <a name="output_rules"></a> [rules](#output\_rules) | Map of created firewall policy rules |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self\_link of the hierarchical firewall policy |
<!-- END_TF_DOCS -->