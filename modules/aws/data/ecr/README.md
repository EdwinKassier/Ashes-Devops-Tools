# AWS ECR Module

Elastic Container Registry repositories — the AWS parity counterpart to GCP's
`modules/gcp/artifact-registry`. Secure defaults: **IMMUTABLE** image tags,
**scan-on-push**, and encryption always on (KMS when a `kms_key_arn` is supplied,
otherwise AES256). Optional per-repository lifecycle policy (expire untagged /
keep last N tagged) and an optional org-scoped pull policy
(`aws:PrincipalOrgID`) — both built with `jsonencode()`.

## Usage

```hcl
module "ecr" {
  source = "../../data/ecr"

  org_id = "o-abc1234567" # optional: grant org-wide pull

  repositories = {
    "platform/api" = {
      kms_key_arn                = "arn:aws:kms:eu-west-2:111122223333:key/abcd"
      expire_untagged_after_days = 14
      keep_last_tagged_images    = 20
    }
    "platform/worker" = {
      image_tag_mutability = "IMMUTABLE"
    }
  }
}
```

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


- resource.aws_ecr_lifecycle_policy.this (modules/aws/data/ecr/main.tf#L35)
- resource.aws_ecr_repository.this (modules/aws/data/ecr/main.tf#L15)
- resource.aws_ecr_repository_policy.org (modules/aws/data/ecr/main.tf#L67)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations ID (o-xxxx). When set, an org-scoped repository policy (aws:PrincipalOrgID) granting pull access to the org is attached to every repository. Null = no repository policy. | `string` | `null` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Map of ECR repositories to create, keyed by repository name. The parity counterpart to GCP's artifact-registry. | <pre>map(object({<br/>    image_tag_mutability = optional(string, "IMMUTABLE")<br/>    scan_on_push         = optional(bool, true)<br/>    kms_key_arn          = optional(string) # null => AES256; set => KMS encryption<br/>    force_delete         = optional(bool, false)<br/>    # Optional lifecycle policy: expire untagged images older than N days and/or<br/>    # keep only the most recent N tagged images. Rendered to JSON via jsonencode.<br/>    expire_untagged_after_days = optional(number)<br/>    keep_last_tagged_images    = optional(number)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every repository. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_registry_ids"></a> [registry\_ids](#output\_registry\_ids) | Map of repository name to the registry (account) ID hosting it. |
| <a name="output_repository_arns"></a> [repository\_arns](#output\_repository\_arns) | Map of repository name to its ARN. |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Map of repository name to its registry URL (for docker push/pull). |
<!-- END_TF_DOCS -->
