# cloud-run

Deploys a single [Cloud Run v2](https://cloud.google.com/run) service — the serverless
application runtime for this landing zone.

Secure by default:

- Runs as a **dedicated service account** (`service_account_email` is required).
- Ingress defaults to `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` — not public.
- Private unless `enable_unauthenticated = true` grants `roles/run.invoker` to `allUsers`.
- `deletion_protection` defaults to **on** via `enable_deletion_protection`.
- Secret env vars are sourced from **Secret Manager** (`value_source.secret_key_ref`),
  never passed as plaintext.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs output goes here — run `make docs` to regenerate -->
<!-- END_TF_DOCS -->

## Usage

```hcl
module "api" {
  source = "../../modules/gcp/compute/cloud-run"

  project_id            = "my-project-id"
  location              = "europe-west1"
  name                  = "my-api"
  image                 = "europe-west1-docker.pkg.dev/my-project-id/apps/api:1.0.0"
  service_account_email = "my-api-run@my-project-id.iam.gserviceaccount.com"

  env_vars = {
    LOG_LEVEL = "info"
  }

  secret_env_vars = [
    {
      name    = "DATABASE_URL"
      secret  = "database-url"
      version = "latest"
    },
  ]
}
```
