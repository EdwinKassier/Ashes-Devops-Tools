# iam-role

Cross-account, workload, and break-glass IAM roles for the SRA landing zone.

The `roles` map builds arbitrary IAM roles from a name-keyed configuration:
each entry supplies its own trust policy (JSON), optional session duration,
managed policy ARNs (attached via separate attachment resources), an optional
inline policy, and an optional permissions boundary. This covers cross-account
access roles and workload execution roles.

The **break-glass** role is a separate, single, opinionated emergency-access
role:

- **Disabled by default.** Its standing state is a `break-glass-deny-all`
  inline policy (`Deny *` on `*`). It only becomes usable when
  `break_glass_active = true` is set during a declared incident, which swaps
  the deny-all policy for the AWS-managed `AdministratorAccess`.
- **MFA required.** The trust policy requires `aws:MultiFactorAuthPresent` and
  bounds `aws:MultiFactorAuthAge`, so a stale or MFA-less session cannot assume
  it.
- **No CloudWatch alarm here.** The break-glass-use alarm lives in the
  `security-notifications` module (C14); this module only defines the role and
  its standing/active policy state.
- **SCP carve-out.** The break-glass principal is carved out of *specific* SCP
  deny statements (by its account-qualified ARN), not exempted from the whole
  SCP. This keeps the emergency role effective during an incident without
  weakening the rest of the guardrails.

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


- resource.aws_iam_role.break_glass (modules/aws/iam-role/main.tf#L57)
- resource.aws_iam_role.this (modules/aws/iam-role/main.tf#L29)
- resource.aws_iam_role_policy.break_glass_standing (modules/aws/iam-role/main.tf#L76)
- resource.aws_iam_role_policy.inline (modules/aws/iam-role/main.tf#L46)
- resource.aws_iam_role_policy_attachment.break_glass_active (modules/aws/iam-role/main.tf#L91)
- resource.aws_iam_role_policy_attachment.this (modules/aws/iam-role/main.tf#L40)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_break_glass_active"></a> [break\_glass\_active](#input\_break\_glass\_active) | Whether the break-glass role is activated for an incident. false (default) => deny-all standing policy; true => AdministratorAccess attached. Flip only during a declared incident. | `bool` | `false` | no |
| <a name="input_break_glass_mfa_max_age"></a> [break\_glass\_mfa\_max\_age](#input\_break\_glass\_mfa\_max\_age) | Maximum age in seconds of the MFA session (aws:MultiFactorAuthAge) permitted to assume the break-glass role. | `number` | `3600` | no |
| <a name="input_break_glass_role_name"></a> [break\_glass\_role\_name](#input\_break\_glass\_role\_name) | Name of the break-glass emergency-access role. | `string` | `"break-glass"` | no |
| <a name="input_break_glass_trusted_principals"></a> [break\_glass\_trusted\_principals](#input\_break\_glass\_trusted\_principals) | Account-qualified IAM principal ARNs allowed to assume the break-glass role (subject to the MFA conditions). Empty by default so no principal can assume it until explicitly configured. | `list(string)` | `[]` | no |
| <a name="input_enable_break_glass"></a> [enable\_break\_glass](#input\_enable\_break\_glass) | Create the break-glass emergency-access role. Disabled-by-default: standing state is a deny-all inline policy. | `bool` | `true` | no |
| <a name="input_roles"></a> [roles](#input\_roles) | Map of IAM role name to its configuration. trust\_policy is a JSON assume-role policy document. managed\_policy\_arns are attached via separate attachment resources; inline\_policy (JSON) is attached as a role inline policy when non-empty. | <pre>map(object({<br/>    trust_policy         = string<br/>    max_session_duration = optional(number, 3600)<br/>    managed_policy_arns  = optional(list(string), [])<br/>    inline_policy        = optional(string, "")<br/>    permissions_boundary = optional(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_break_glass_role_arn"></a> [break\_glass\_role\_arn](#output\_break\_glass\_role\_arn) | ARN of the break-glass role, or null when enable\_break\_glass is false. |
| <a name="output_role_arns"></a> [role\_arns](#output\_role\_arns) | Map of role name to role ARN for the roles created from var.roles. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "iam_role" {
  source = "../../modules/aws/iam-role"

  roles = {
    cross-account-audit = {
      trust_policy = jsonencode({
        Version   = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::111111111111:root" }
          Action    = "sts:AssumeRole"
        }]
      })
      managed_policy_arns = ["arn:aws:iam::aws:policy/SecurityAudit"]
    }
  }

  # Break-glass is enabled and deny-all by default; wire the incident-commander
  # principal(s) here. Flip break_glass_active only during a declared incident.
  break_glass_trusted_principals = ["arn:aws:iam::222222222222:role/incident-commander"]
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
