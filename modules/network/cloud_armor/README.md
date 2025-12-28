# Cloud Armor Module

This module manages Google Cloud Armor security policies, providing DDoS protection and WAF (Web Application Firewall) capabilities.

## Features

- **OWASP Top 10**: Pre-configured ruleset to block common web attacks (SQLi, XSS, RCE, etc.).
- **DDoS Protection**: Managed protection against volumetric attacks.
- **Custom Rules**: Support for custom allow/deny logic based on IP, geolocation, or headers.
- **Sensitivity Tuning**: Adjustable sensitivity levels for WAF rules.

## Usage

```hcl
module "cloud_armor" {
  source = "./modules/network/cloud_armor"

  project_id = "my-project-id"
  name       = "edge-security-policy"
  
  # Enable OWASP Protection
  enable_owasp_rules = true
  owasp_sensitivity  = 1  # 0-4
  
  # Custom Whitelist
  custom_rules = {
    "allow-office-vpn" = {
      action      = "allow"
      priority    = 1000
      expression  = "inIpRange(origin.ip, '203.0.113.0/24')"
      description = "Allow Office IP"
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `name` | Policy name | `string` | n/a | yes |
| `enable_owasp_rules` | Enable OWASP CRS | `bool` | `true` | no |
| `owasp_sensitivity` | WAF sensitivity (0-4) | `number` | `1` | no |
| `custom_rules` | Map of custom rules | `map(object)` | `{}` | no |
| `default_rule_action`| Default action (`allow`/`deny`) | `string` | `"deny"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `policy_self_link` | URI of the security policy |
| `policy_name` | Name of the policy |
