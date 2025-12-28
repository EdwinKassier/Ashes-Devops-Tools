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
