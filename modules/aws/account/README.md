# account

AWS Organizations member-account vending for the SRA landing zone. Creates a
single member account under a given OU with a module-managed `managed-by`
tag, an organization-created cross-account access role, and optional alternate
contacts (SECURITY / BILLING / OPERATIONS).

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	account_name = 
	email = 
	parent_ou_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_account_alternate_contact.this (modules/aws/account/main.tf#L22)
- resource.aws_organizations_account.this (modules/aws/account/main.tf#L9)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_name"></a> [account\_name](#input\_account\_name) | Human-readable name of the member account (e.g. "log-archive"). | `string` | n/a | yes |
| <a name="input_email"></a> [email](#input\_email) | Root email address for the member account. Must be unique across all AWS accounts. | `string` | n/a | yes |
| <a name="input_parent_ou_id"></a> [parent\_ou\_id](#input\_parent\_ou\_id) | ID of the organizational unit (or root) the account is placed under. | `string` | n/a | yes |
| <a name="input_alternate_contacts"></a> [alternate\_contacts](#input\_alternate\_contacts) | Alternate contacts to register on the account, keyed by an arbitrary label. contact\_type must be one of SECURITY, BILLING, or OPERATIONS. | <pre>map(object({<br/>    contact_type  = string # one of: SECURITY, BILLING, OPERATIONS<br/>    name          = string<br/>    title         = string<br/>    email_address = string<br/>    phone_number  = string<br/>  }))</pre> | `{}` | no |
| <a name="input_close_on_deletion"></a> [close\_on\_deletion](#input\_close\_on\_deletion) | Whether to close the AWS account when the resource is destroyed (instead of only removing it from the organization). | `bool` | `false` | no |
| <a name="input_cross_account_role_name"></a> [cross\_account\_role\_name](#input\_cross\_account\_role\_name) | Name of the IAM role automatically created in the member account for cross-account access from the management account. | `string` | `"OrganizationAccountAccessRole"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the account. Merged with the module-managed managed-by=terraform tag. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_arn"></a> [account\_arn](#output\_account\_arn) | The ARN of the member account. |
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | The ID of the member account. |
| <a name="output_cross_account_role_arn"></a> [cross\_account\_role\_arn](#output\_cross\_account\_role\_arn) | ARN of the cross-account access role created in the member account. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "account" {
  source = "../../modules/aws/account"

  account_name = "log-archive"
  email        = "aws+logarchive@example.com"
  parent_ou_id = "ou-abc1-def2ghi3"

  alternate_contacts = {
    security = {
      contact_type  = "SECURITY"
      name          = "Security Team"
      title         = "Security Contact"
      email_address = "security@example.com"
      phone_number  = "+1-555-0100"
    }
  }
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
