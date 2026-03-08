# Network Firewall Module

This module manages hierarchical firewall rules for a VPC network. It is designed to be used multiple times to create "tiers" of security (e.g., Allow Public -> Compute, Allow Compute -> DB).

## Features

- **Directional**: Supports both `INGRESS` and `EGRESS` rules.
- **Tag-Based**: Targets traffic based on Source/Target Network Tags or Service Accounts.
- **Logging**: Configurable firewall rule logging.
- **Priority**: Explicit priority management.

## Usage

```hcl
module "fw_allow_internal" {
  source = "./modules/network/network-firewall"

  project_id         = "my-project-id"
  firewall_rule_name = "allow-internal-traffic"
  network            = "my-vpc"
  priority           = 65534
  
  allow_rules = [{
    protocol = "tcp"
    ports    = ["0-65535"]
  }]
  
  source_ranges = ["10.0.0.0/8"]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `firewall_rule_name`| Name of the rule | `string` | n/a | yes |
| `network` | VPC network name (not URI) | `string` | n/a | yes |
| `allow_rules` | List of allow protocols/ports | `list(object)` | `[]` | no |
| `deny_rules` | List of deny protocols/ports | `list(object)` | `[]` | no |
| `source_ranges` | Source CIDR ranges | `list(string)` | `[]` | no |
| `source_tags` | Source network tags | `list(string)` | `[]` | no |
| `target_tags` | Target network tags | `list(string)` | `[]` | no |
| `priority` | Rule priority (0-65535) | `number` | `1000` | no |

## Outputs

| Name | Description |
|------|-------------|
| `firewall_rule` | The created firewall rule resource |
| `self_link` | The URI of the firewall rule |

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	firewall_rule_name = 
	network = 
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


- resource.google_compute_firewall.firewall_rule (modules/network/network-firewall/main.tf#L1)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_firewall_rule_name"></a> [firewall\_rule\_name](#input\_firewall\_rule\_name) | Name of the firewall rule | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The name or self\_link of the network to attach the firewall rule to | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where the firewall rule will be created | `string` | n/a | yes |
| <a name="input_allow_rules"></a> [allow\_rules](#input\_allow\_rules) | List of allow rules with protocol and ports | <pre>list(object({<br/>    protocol = string<br/>    ports    = optional(list(string))<br/>  }))</pre> | `[]` | no |
| <a name="input_deny_rules"></a> [deny\_rules](#input\_deny\_rules) | List of deny rules with protocol and ports | <pre>list(object({<br/>    protocol = string<br/>    ports    = optional(list(string))<br/>  }))</pre> | `[]` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the firewall rule | `string` | `null` | no |
| <a name="input_direction"></a> [direction](#input\_direction) | Direction of the firewall rule (INGRESS or EGRESS) | `string` | `"INGRESS"` | no |
| <a name="input_disabled"></a> [disabled](#input\_disabled) | Denotes whether the firewall rule is disabled | `bool` | `false` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Whether to enable logging for the firewall rule | `bool` | `false` | no |
| <a name="input_log_metadata"></a> [log\_metadata](#input\_log\_metadata) | Logging metadata configuration (INCLUDE\_ALL\_METADATA or EXCLUDE\_ALL\_METADATA) | `string` | `"INCLUDE_ALL_METADATA"` | no |
| <a name="input_priority"></a> [priority](#input\_priority) | Priority of the firewall rule (default: 1000) | `number` | `1000` | no |
| <a name="input_source_ranges"></a> [source\_ranges](#input\_source\_ranges) | List of source IP CIDR ranges | `list(string)` | `null` | no |
| <a name="input_source_tags"></a> [source\_tags](#input\_source\_tags) | List of source tags for the firewall rule | `list(string)` | `null` | no |
| <a name="input_target_tags"></a> [target\_tags](#input\_target\_tags) | List of target tags for the firewall rule | `list(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_firewall_rule_creation_timestamp"></a> [firewall\_rule\_creation\_timestamp](#output\_firewall\_rule\_creation\_timestamp) | Creation timestamp of the firewall rule |
| <a name="output_firewall_rule_id"></a> [firewall\_rule\_id](#output\_firewall\_rule\_id) | The ID of the created firewall rule (deprecated: use 'id' instead) |
| <a name="output_firewall_rule_self_link"></a> [firewall\_rule\_self\_link](#output\_firewall\_rule\_self\_link) | The self\_link of the created firewall rule (deprecated: use 'self\_link' instead) |
| <a name="output_id"></a> [id](#output\_id) | The ID of the created firewall rule |
| <a name="output_name"></a> [name](#output\_name) | The name of the created firewall rule |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The self\_link of the created firewall rule |
<!-- END_TF_DOCS -->