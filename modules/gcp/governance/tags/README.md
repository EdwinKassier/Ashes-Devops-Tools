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
      description = "Deployment environment tier"
      values      = ["dev", "uat", "prod"]
    }
    "cost-center" = {
      description = "Owning department for cost allocation"
      values      = ["engineering", "marketing"]
    }
    "data-classification" = {
      # description is optional — defaults to "Managed by Terraform"
      values = ["public", "internal", "confidential", "restricted"]
    }
  }
}
```

> **`values` is a `list(string)`**, not a map. Each string becomes one `google_tags_tag_value`
> resource whose `short_name` is the list element itself.
> Each tag key also accepts an optional `description` field (defaults to `"Managed by Terraform"`)
> that is displayed in the GCP console.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |



## Resources

The following resources are created:


- resource.google_tags_tag_key.keys (modules/governance/tags/main.tf#L4)
- resource.google_tags_tag_value.values (modules/governance/tags/main.tf#L12)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The numeric Organization ID where tags will be defined (digits only, without 'organizations/' prefix) | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of Tag Keys to their configuration. Each entry creates one Tag Key and its<br/>allowed Tag Values under the organization.<br/><br/>Keys and value short\_names follow GCP tag constraints: 1–63 characters, must<br/>start with a lowercase letter, may contain lowercase letters, digits, hyphens,<br/>and underscores. No spaces or uppercase.<br/><br/>The optional `description` field sets a human-readable description on both the<br/>Tag Key resource and each of its Tag Values. Defaults to "Managed by Terraform"<br/>when omitted.<br/><br/>Example:<br/>  tags = {<br/>    "environment" = {<br/>      values      = ["dev", "staging", "prod"]<br/>      description = "Deployment environment tier"<br/>    }<br/>    "cost-center" = {<br/>      values = ["engineering", "marketing"]<br/>    }<br/>  } | <pre>map(object({<br/>    values      = list(string)<br/>    description = optional(string, "Managed by Terraform")<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_tag_keys"></a> [tag\_keys](#output\_tag\_keys) | Map of Tag Key Short Names to their Resource Names (IDs) |
| <a name="output_tag_values"></a> [tag\_values](#output\_tag\_values) | Map of Tag Value Short Names to their Resource Names (IDs) |
<!-- END_TF_DOCS -->