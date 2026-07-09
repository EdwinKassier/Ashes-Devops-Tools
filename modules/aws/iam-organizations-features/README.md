# iam-organizations-features

Centralized root-access management for the SRA landing zone. Enables the
organization-wide IAM features (`RootCredentialsManagement`, `RootSessions`)
that let the management account centrally manage root credentials for MEMBER
accounts.

> **Run from the management account.** This module wraps
> `aws_iam_organizations_features`, which must be applied with the
> management-account provider. It requires `iam.amazonaws.com` trusted access on
> the organization — enabled by the [`organization`](../organization/) module
> via `aws_service_access_principals`. Once enabled, member-account root
> credentials are managed centrally rather than held by each member account.
>
> `aws_iam_organizations_features` is verified to exist in the AWS provider
> `>= 6.46`.

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


- resource.aws_iam_organizations_features.this (modules/aws/iam-organizations-features/main.tf#L12)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enabled_features"></a> [enabled\_features](#input\_enabled\_features) | IAM organization features to enable for centralized root access management. Valid values are RootCredentialsManagement (centrally manage member-account root credentials) and RootSessions (perform privileged root actions in member accounts from the management account). | `list(string)` | <pre>[<br/>  "RootCredentialsManagement",<br/>  "RootSessions"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_enabled_features"></a> [enabled\_features](#output\_enabled\_features) | The IAM organization features enabled for centralized root access management. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "iam_organizations_features" {
  source = "../../modules/aws/iam-organizations-features"

  # Defaults enable both RootCredentialsManagement and RootSessions org-wide.
  # Override only to enable a subset.
  enabled_features = ["RootCredentialsManagement", "RootSessions"]
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
