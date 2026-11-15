# `envs/aws/shared-services` (workspace `aws-shared-services`)

Shared platform services in the shared-services account: the private certificate authority and the Secrets Manager baseline. It reads the `aws-organization` contract. Most inputs default to a key in `config/landing-zone.yaml`; an explicit variable (tfvars or an HCP Terraform workspace variable) wins over the config file. The description of each input names its config key.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_assume_role_arn"></a> [assume\_role\_arn](#input\_assume\_role\_arn) | Optional role the aws provider(s) assume. Default null: the workspace's TFC dynamic credentials (TFC\_AWS\_PROVIDER\_AUTH + TFC\_AWS\_PLAN\_ROLE\_ARN / TFC\_AWS\_APPLY\_ROLE\_ARN, from the aws-organization outputs tfc\_plan\_role\_arns / tfc\_apply\_role\_arns) already resolve to the target member account, so no hop is made. Legacy / local runs from management-account credentials set this to the account's account\_role\_arns entry (OrganizationAccountAccessRole). | `string` | `null` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region the shared services are deployed in and the region the default provider assumes the shared-services-account role in. Null = org.regions.aws from config/landing-zone.yaml, else eu-west-2. | `string` | `null` | no |
| <a name="input_ca_common_name"></a> [ca\_common\_name](#input\_ca\_common\_name) | Common name (CN) placed in the CA certificate subject. | `string` | `"org-internal-ca"` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | Value of the CostCenter cost-allocation tag on every resource in this root. Null = org.cost\_center from config/landing-zone.yaml, else "platform". | `string` | `null` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Extra tags merged into the aws provider default\_tags (after the canonical set, so they may override it). Values must be non-empty. | `map(string)` | `{}` | no |
| <a name="input_enable_private_ca"></a> [enable\_private\_ca](#input\_enable\_private\_ca) | Whether to create the org-shared ACM Private CA. COST TOGGLE: ACM PCA bills a fixed monthly charge per CA from creation. Off by default. | `bool` | `false` | no |
| <a name="input_enable_secrets_baseline"></a> [enable\_secrets\_baseline](#input\_enable\_secrets\_baseline) | Whether to create the org Secrets Manager baseline (org-scoped secrets + optional rotation). Off by default. | `bool` | `false` | no |
| <a name="input_landing_zone_config_path"></a> [landing\_zone\_config\_path](#input\_landing\_zone\_config\_path) | Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), relative to this root (a .yaml or .yml file inside the repository). Null = ../../../config/landing-zone.yaml; "" disables the lookup. When set, the file must exist (the plan fails otherwise); the default path is read only if the file exists; explicit variables win over its values. | `string` | `null` | no |
| <a name="input_landing_zone_name"></a> [landing\_zone\_name](#input\_landing\_zone\_name) | Landing-zone identifier written to the LandingZone tag on every resource. Null = org.name from config/landing-zone.yaml (the single source shared by every AWS root). The upstream placeholders "ashes" and "my-org" are rejected. | `string` | `null` | no |
| <a name="input_organization_contract"></a> [organization\_contract](#input\_organization\_contract) | aws-organization stage contract (FAST-style override), the same type in every aws root: organization\_id (o-xxxxxxxxxx), organization\_root\_id (r-xxxx), management\_account\_id, ou\_ids (OU name => OU ID), account\_ids (account key => 12-digit ID), account\_role\_arns (account key => cross-account role ARN). This root needs: organization\_id, management\_account\_id, account\_ids. When set, the aws-organization remote state is NOT read. Null = aws.contracts.organization from config/landing-zone.yaml, else the contract output of the organization\_workspace\_name workspace. | <pre>object({<br/>    organization_id       = optional(string)<br/>    organization_root_id  = optional(string)<br/>    management_account_id = optional(string)<br/>    ou_ids                = optional(map(string), {})<br/>    account_ids           = map(string)<br/>    account_role_arns     = optional(map(string), {})<br/>  })</pre> | `null` | no |
| <a name="input_organization_workspace_name"></a> [organization\_workspace\_name](#input\_organization\_workspace\_name) | Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from. | `string` | `"aws-organization"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Value of the Owner cost-allocation tag on every resource in this root (team or distribution list). Null = org.owner from config/landing-zone.yaml, else "platform-team". | `string` | `null` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Map of secret name to its configuration. rotation\_lambda\_arn, when set, enables automatic rotation for that secret; rotation\_days controls the rotation interval. | <pre>map(object({<br/>    rotation_lambda_arn = optional(string, "")<br/>    rotation_days       = optional(number, 30)<br/>  }))</pre> | `{}` | no |
| <a name="input_secrets_kms_key_id"></a> [secrets\_kms\_key\_id](#input\_secrets\_kms\_key\_id) | ARN or ID of a customer-managed KMS key used to encrypt all baseline secrets. When empty, secrets use the account default aws/secretsmanager managed key. | `string` | `""` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via the TF\_CLOUD\_ORGANIZATION environment variable (kept out of the code so the same root works across orgs and CI). Null = org.tfc.organization from config/landing-zone.yaml. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ca_arn"></a> [ca\_arn](#output\_ca\_arn) | ARN of the org-shared ACM Private CA, or null when the Private CA capability is disabled. |
| <a name="output_secret_arns"></a> [secret\_arns](#output\_secret\_arns) | Map of baseline secret name to its ARN. Empty when the Secrets Manager baseline is disabled. |
<!-- END_TF_DOCS -->
