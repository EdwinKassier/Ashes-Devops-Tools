# iam-identity-center

AWS IAM Identity Center (successor to AWS SSO) permission sets, account
assignments, and optional ABAC configuration, managed **within an existing
Identity Center instance**.

## Operating model

- **The instance is enabled out-of-band.** There is no Terraform resource that
  creates an Identity Center instance. It must be enabled once (console or
  `aws sso-admin` / Organizations API) in the organization management account
  before this module runs. The module discovers it via
  `data.aws_ssoadmin_instances` and manages only permission sets and
  assignments inside it.
- **Assign GROUPS, not users.** Bind permission sets to Identity Store *groups*
  (`principal_type = "GROUP"`) so membership is managed in the IdP. Reserve
  `USER` principals for the management account break-glass path only.
- **ABAC via session tags.** Set `enable_abac = true` and supply
  `abac_attributes` to surface IdP/session attributes as `aws:PrincipalTag`
  values that permission-set policies can condition on.
- **Block `identitystore:*` mutations via SCP.** To prevent drift, deny direct
  Identity Store user/group mutations (`identitystore:CreateUser`,
  `identitystore:CreateGroup`, `identitystore:Delete*`, etc.) outside this
  pipeline with a service control policy, so group membership stays sourced
  from the IdP and Terraform state stays authoritative.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	
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


- resource.aws_ssoadmin_account_assignment.this (modules/aws/iam-identity-center/main.tf#L56)
- resource.aws_ssoadmin_instance_access_control_attributes.this (modules/aws/iam-identity-center/main.tf#L69)
- resource.aws_ssoadmin_managed_policy_attachment.this (modules/aws/iam-identity-center/main.tf#L40)
- resource.aws_ssoadmin_permission_set.this (modules/aws/iam-identity-center/main.tf#L31)
- resource.aws_ssoadmin_permission_set_inline_policy.this (modules/aws/iam-identity-center/main.tf#L48)
- data source.aws_ssoadmin_instances.this (modules/aws/iam-identity-center/main.tf#L12)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_abac_attributes"></a> [abac\_attributes](#input\_abac\_attributes) | Map of ABAC attribute key to the list of attribute sources (identity-store or IdP attribute paths) that populate it. Only used when enable\_abac is true. | `map(list(string))` | `{}` | no |
| <a name="input_assignments"></a> [assignments](#input\_assignments) | Map of assignment key to an assignment binding a permission set to a principal (GROUP or USER) in a target AWS account. permission\_set must be a key in permission\_sets. Prefer GROUP principals; reserve USER for the management account only. | <pre>map(object({<br/>    permission_set = string<br/>    principal_type = string # GROUP | USER<br/>    principal_id   = string # Identity Store group or user ID<br/>    account_id     = string # Target AWS account ID<br/>  }))</pre> | `{}` | no |
| <a name="input_enable_abac"></a> [enable\_abac](#input\_enable\_abac) | Whether to enable attribute-based access control on the Identity Center instance, allowing session/IdP attributes to be referenced in permission-set policies via aws:PrincipalTag. | `bool` | `false` | no |
| <a name="input_permission_sets"></a> [permission\_sets](#input\_permission\_sets) | Map of permission set name to its definition. session\_duration is an ISO-8601 duration (e.g. PT1H). managed\_policy\_arns are AWS-managed policy ARNs attached to the set; inline\_policy is an optional inline IAM policy JSON document. | <pre>map(object({<br/>    description         = string<br/>    session_duration    = string<br/>    managed_policy_arns = optional(list(string), [])<br/>    inline_policy       = optional(string, "")<br/>  }))</pre> | <pre>{<br/>  "AdministratorAccess": {<br/>    "description": "Full administrative access. Assign only to break-glass groups.",<br/>    "managed_policy_arns": [<br/>      "arn:aws:iam::aws:policy/AdministratorAccess"<br/>    ],<br/>    "session_duration": "PT1H"<br/>  },<br/>  "ReadOnly": {<br/>    "description": "Organization-wide read-only access for auditors and viewers.",<br/>    "managed_policy_arns": [<br/>      "arn:aws:iam::aws:policy/ReadOnlyAccess"<br/>    ],<br/>    "session_duration": "PT1H"<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instance_arn"></a> [instance\_arn](#output\_instance\_arn) | The ARN of the discovered (out-of-band) IAM Identity Center instance these permission sets and assignments are managed within. |
| <a name="output_permission_set_arns"></a> [permission\_set\_arns](#output\_permission\_set\_arns) | Map of permission set name to its ARN. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "iam_identity_center" {
  source = "../../modules/aws/iam-identity-center"

  # Defaults already provide AdministratorAccess and ReadOnly permission sets.
  assignments = {
    admins-management = {
      permission_set = "AdministratorAccess"
      principal_type = "GROUP"
      principal_id   = "<identity-store-group-id>"
      account_id     = "<management-account-id>"
    }
  }
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
