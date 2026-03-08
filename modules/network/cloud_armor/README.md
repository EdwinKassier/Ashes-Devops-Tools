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

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	policy_name = 
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
| <a name="provider_google"></a> [google](#provider\_google) | 6.50.0 |



## Resources

The following resources are created:


- resource.google_compute_security_policy.policy (modules/network/cloud_armor/main.tf#L1)
- resource.google_compute_security_policy_rule.owasp_rules (modules/network/cloud_armor/main.tf#L118)
- resource.google_compute_security_policy_rule.preconfigured_waf_rules (modules/network/cloud_armor/main.tf#L135)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | Name of the Cloud Armor security policy | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The project ID where the security policy will be created | `string` | n/a | yes |
| <a name="input_custom_rules"></a> [custom\_rules](#input\_custom\_rules) | Map of custom rules to apply to the security policy | <pre>map(object({<br/>    action      = string<br/>    priority    = number<br/>    description = optional(string)<br/>    match_conditions = object({<br/>      versioned_expr = string<br/>      config = object({<br/>        src_ip_ranges = list(string)<br/>      })<br/>    })<br/>    rate_limit_options = optional(object({<br/>      threshold_count     = number<br/>      interval_sec        = number<br/>      conform_action      = optional(string)<br/>      exceed_action       = optional(string)<br/>      enforce_on_key      = optional(string)<br/>      enforce_on_key_type = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_default_rule_action"></a> [default\_rule\_action](#input\_default\_rule\_action) | Default rule action (allow/deny) | `string` | `"allow"` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the Cloud Armor security policy | `string` | `"Cloud Armor security policy managed by Terraform"` | no |
| <a name="input_enable_adaptive_protection"></a> [enable\_adaptive\_protection](#input\_enable\_adaptive\_protection) | Enable adaptive protection features | `bool` | `false` | no |
| <a name="input_enable_log4j_protection"></a> [enable\_log4j\_protection](#input\_enable\_log4j\_protection) | Enable the Cloud Armor canary rule that blocks Log4Shell-style payloads | `bool` | `true` | no |
| <a name="input_enable_owasp_rules"></a> [enable\_owasp\_rules](#input\_enable\_owasp\_rules) | Enable preconfigured OWASP ModSecurity Core Rule Set | `bool` | `false` | no |
| <a name="input_owasp_sensitivity"></a> [owasp\_sensitivity](#input\_owasp\_sensitivity) | OWASP rule sensitivity level (1-4, lower is more sensitive) | `number` | `2` | no |
| <a name="input_preconfigured_waf_rules"></a> [preconfigured\_waf\_rules](#input\_preconfigured\_waf\_rules) | Additional preconfigured WAF rules to enable | <pre>list(object({<br/>    rule_id     = string<br/>    action      = string<br/>    priority    = number<br/>    description = optional(string)<br/>    sensitivity = optional(number, 2)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_fingerprint"></a> [fingerprint](#output\_fingerprint) | Fingerprint of the security policy |
| <a name="output_id"></a> [id](#output\_id) | The ID of the created security policy |
| <a name="output_name"></a> [name](#output\_name) | The name of the created security policy |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | The ID of the created security policy (deprecated: use 'id' instead) |
| <a name="output_policy_name"></a> [policy\_name](#output\_policy\_name) | The name of the created security policy (deprecated: use 'name' instead) |
| <a name="output_policy_self_link"></a> [policy\_self\_link](#output\_policy\_self\_link) | The self\_link of the created security policy (deprecated: use 'self\_link' instead) |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self\_link of the created security policy |
<!-- END_TF_DOCS -->