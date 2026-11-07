# secret-manager

Creates application secret **containers** in [Secret Manager](https://cloud.google.com/secret-manager),
their replication policy, and per-secret accessor IAM bindings. This is the GCP app
secret store (audit gap M4).

Secure by default:

- Secret **values are not managed here** by default — only containers, replication and
  IAM — so no plaintext lands in Terraform state.
- Replication is **automatic** unless `user_managed_regions` is supplied.
- Accessors receive only `roles/secretmanager.secretAccessor`, scoped per secret.
- `enable_deletion_protection` defaults to **on**.

Set production values **out of band** (console, a privileged CI service account, or
`gcloud secrets versions add`). `var.secret_values` creates initial versions and is
intended for bootstrap / non-production only — it is `sensitive`, but the value still
enters Terraform state.

> CMEK note: for `user_managed` replication the same `kms_key_name` is applied to every
> replica, so a multi-region user-managed secret needs a key that is valid in each
> region. Use automatic replication, or one secret per region, when that does not hold.

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Secret Manager Module - Main Configuration

Creates application secret CONTAINERS in Secret Manager. Secret values are not
managed here by default — only container metadata, replication and IAM — so no
plaintext lands in Terraform state. An optional initial version can be supplied
per secret via var.secret\_values for bootstrap/non-production use.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |



## Resources

The following resources are created:


- resource.google_secret_manager_secret.this (modules/gcp/data/secret-manager/main.tf#L38)
- resource.google_secret_manager_secret_iam_member.accessor (modules/gcp/data/secret-manager/main.tf#L102)
- resource.google_secret_manager_secret_version.this (modules/gcp/data/secret-manager/main.tf#L82)
- resource.terraform_data.deletion_protection_guard (modules/gcp/data/secret-manager/main.tf#L28)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where the secrets are created. | `string` | n/a | yes |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Prevent accidental destruction of this module's secrets.<br/><br/>When true, a terraform\_data guard resource is created with prevent\_destroy = true.<br/>Terraform refuses to destroy the module while the guard exists. To intentionally<br/>remove protected secrets, first run:<br/>  terraform state rm 'module.<name>.terraform\_data.deletion\_protection\_guard' | `bool` | `true` | no |
| <a name="input_ephemeral_secret_values"></a> [ephemeral\_secret\_values](#input\_ephemeral\_secret\_values) | Ephemeral initial secret VALUES as secret\_name => value, for secrets declared in<br/>var.secrets with ephemeral\_value = true. Written with the write-only secret\_data\_wo<br/>argument and never stored in plan or state; feed it from an ephemeral resource or an<br/>ephemeral root variable. Prefer this over secret\_values, whose value must be known<br/>to (and is held in memory by) the calling configuration. Bump secret\_value\_versions<br/>to push a new value. | `map(string)` | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every labelable resource this module creates (merged with the provider default\_labels; resource-specific labels win). | `map(string)` | `{}` | no |
| <a name="input_secret_accessors"></a> [secret\_accessors](#input\_secret\_accessors) | Map of secret name => list of IAM members granted roles/secretmanager.secretAccessor<br/>on that secret (e.g. "serviceAccount:app@project.iam.gserviceaccount.com"). Every key<br/>must also exist in var.secrets. | `map(list(string))` | `{}` | no |
| <a name="input_secret_value_versions"></a> [secret\_value\_versions](#input\_secret\_value\_versions) | Per-secret write-only version counter (secret\_name => integer, default 1). Write-only values are not diffed, so increment a secret's counter to push a new value from secret\_values. | `map(number)` | `{}` | no |
| <a name="input_secret_values"></a> [secret\_values](#input\_secret\_values) | Optional initial secret VALUES as secret\_name => value. A google\_secret\_manager\_secret\_version<br/>is created ONLY for the names present here, using the write-only secret\_data\_wo argument,<br/>so the plaintext is never stored in Terraform plan or state (Terraform >= 1.11). Pass an<br/>ephemeral value where possible. Every key must also exist in var.secrets. | `map(string)` | `{}` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Map of secret name => configuration. Each secret creates a container only; secret<br/>VALUES are not managed here by default (see var.secret\_values).<br/>  labels      = labels applied to the secret<br/>  replication = { automatic = bool, user\_managed\_regions = list(string) }<br/>                When user\_managed\_regions is non-empty, user-managed replication<br/>                is used; otherwise replication is automatic.<br/>  kms\_key\_name = optional CMEK key. For automatic replication a single multi-region<br/>                 key; for user-managed replication the key is applied to each<br/>                 replica (keys must be valid in each region — see README).<br/>  ephemeral\_value = when true, an initial version is created from the ephemeral<br/>                    var.ephemeral\_secret\_values[name] instead of var.secret\_values.<br/>                    The flag lives here because the version set must stay<br/>                    non-ephemeral (an ephemeral map cannot drive for\_each). | <pre>map(object({<br/>    labels = optional(map(string), {})<br/>    replication = optional(object({<br/>      automatic            = optional(bool, true)<br/>      user_managed_regions = optional(list(string), [])<br/>    }), {})<br/>    kms_key_name    = optional(string)<br/>    ephemeral_value = optional(bool, false)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_secret_ids"></a> [secret\_ids](#output\_secret\_ids) | Map of secret name => fully qualified secret id (projects/<p>/secrets/<name>). |
| <a name="output_secret_names"></a> [secret\_names](#output\_secret\_names) | List of created secret names. |
| <a name="output_secret_short_ids"></a> [secret\_short\_ids](#output\_secret\_short\_ids) | Map of secret name => short secret\_id. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "app_secrets" {
  source = "../../modules/gcp/data/secret-manager"

  project_id = "my-project-id"

  secrets = {
    database-url = {
      labels = { app = "api" }
    }
    stripe-key = {
      replication = {
        user_managed_regions = ["europe-west1", "europe-west4"]
      }
    }
  }

  # Grant the app's runtime SA read access.
  secret_accessors = {
    database-url = ["serviceAccount:api-run@my-project-id.iam.gserviceaccount.com"]
    stripe-key   = ["serviceAccount:api-run@my-project-id.iam.gserviceaccount.com"]
  }

  # Values set out of band in production; omit secret_values entirely.
}
```
