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

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	org_id = 
	tags = 
	
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


- resource.google_tags_tag_key.keys (modules/governance/tags/main.tf#L4)
- resource.google_tags_tag_value.values (modules/governance/tags/main.tf#L12)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The Organization ID where tags will be defined | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of Tag Keys to a list of allowed Tag Values | `map(list(string))` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_tag_keys"></a> [tag\_keys](#output\_tag\_keys) | Map of Tag Key Short Names to their Resource Names (IDs) |
| <a name="output_tag_values"></a> [tag\_values](#output\_tag\_values) | Map of Tag Value Short Names to their Resource Names (IDs) |
<!-- END_TF_DOCS -->