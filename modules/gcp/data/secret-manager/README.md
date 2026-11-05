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
<!-- terraform-docs output goes here — run `make docs` to regenerate -->
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
