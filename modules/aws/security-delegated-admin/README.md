# security-delegated-admin

Registers delegated administrators for the organization services that do **not**
have a dedicated `*_organization_admin_account` / `*_delegated_admin_account`
resource of their own.

This module runs from the organization **management account**: the default
provider IS the management account, so no aliased provider is required
(`aws_organizations_delegated_administrator` must be created from the management
account).

The effective registration map is either the explicit `registrations` input
(service principal → delegated-admin account ID) or, when that is left empty, a
convenience default assembled from `security_tooling_account_id` and
`identity_account_id`.

## Default registration set

| Service principal | Delegated to | Notes |
|-------------------|--------------|-------|
| `access-analyzer.amazonaws.com` | Security Tooling | IAM Access Analyzer org |
| `config.amazonaws.com` | Security Tooling | AWS Config org |
| `config-multiaccountsetup.amazonaws.com` | Security Tooling | Config multi-account setup |
| `cloudtrail.amazonaws.com` | Security Tooling | Organization trail admin |
| `fms.amazonaws.com` | Security Tooling | Firewall Manager |
| `ssm.amazonaws.com` | Security Tooling | Systems Manager |
| `resource-explorer-2.amazonaws.com` | Security Tooling | Resource Explorer (index/view created in `org-security-service`) |
| `securitylake.amazonaws.com` | Security Tooling | Security Lake |
| `sso.amazonaws.com` | Identity | IAM Identity Center |

## Services delegated ELSEWHERE (do not add them here)

The following services have their own dedicated delegated-admin resource and are
registered by their respective modules, **not** here. Adding them to this module
would double-register the delegated administrator and fail the apply:

| Service | Dedicated resource | Registered by |
|---------|--------------------|---------------|
| GuardDuty | `aws_guardduty_organization_admin_account` | `aws/guardduty-org` |
| Macie | `aws_macie2_organization_admin_account` | `aws/org-security-service` |
| Inspector | `aws_inspector2_delegated_admin_account` | `aws/org-security-service` |
| Detective | `aws_detective_organization_admin_account` | `aws/org-security-service` |
| Security Hub | `aws_securityhub_organization_admin_account` | `aws/securityhub-org` |

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	identity_account_id = 
	security_tooling_account_id = 
	
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


- resource.aws_organizations_delegated_administrator.this (modules/aws/security-delegated-admin/main.tf#L39)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_identity_account_id"></a> [identity\_account\_id](#input\_identity\_account\_id) | 12-digit account ID of the Identity account, used as the delegated administrator for IAM Identity Center (sso.amazonaws.com) in the default registration set. Ignored when registrations is non-empty. | `string` | n/a | yes |
| <a name="input_security_tooling_account_id"></a> [security\_tooling\_account\_id](#input\_security\_tooling\_account\_id) | 12-digit account ID of the Security Tooling account, used as the delegated administrator for the security services in the default registration set (Access Analyzer, Backup, Config, CloudTrail, FMS, SSM, Resource Explorer, Security Lake). Ignored when registrations is non-empty. | `string` | n/a | yes |
| <a name="input_registrations"></a> [registrations](#input\_registrations) | Explicit map of AWS service principal to the account ID nominated as that service's delegated administrator. When non-empty this overrides the convenience default built from security\_tooling\_account\_id and identity\_account\_id. Do NOT include services that have a dedicated admin resource (guardduty, macie, inspector, detective, securityhub) — they are registered elsewhere. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_registered_services"></a> [registered\_services](#output\_registered\_services) | Service principals for which a delegated administrator was registered (the keys of the effective registration map). |
<!-- END_TF_DOCS -->
