# Troubleshooting Guide

Common local and workflow failures for this repository.

## `make install` finishes but Terraform is still missing

`make install` manages repo tooling, not Terraform itself.

```bash
terraform version
```

If Terraform is missing, install it separately before running any Terraform command.

## `make validate-all` fails with `Failed to query available provider packages`

`make validate-all` runs `terraform init -backend=false` for each supported root. It still needs access to `registry.terraform.io`.

Check:

- outbound network access
- DNS resolution
- proxy settings

## `make lint` fails with `Unrecognized remote plugin message`

That usually means the local TFLint Google ruleset plugin is broken or incompatible.

Reset the plugin cache:

```bash
rm -rf ~/.tflint.d/plugins
tflint --init
make lint
```

## `make docs-check` reports a README is out of date

Regenerate docs and re-run the check:

```bash
make docs
make docs-check
```

If the file is still out of date, confirm the module has:

- `main.tf`
- `variables.tf`
- `outputs.tf`
- `versions.tf`
- `README.md`

## `make security` fails

The local security target runs TFSec and Checkov.

Use the component commands while debugging:

```bash
tfsec . --config-file .tfsec.yml --exclude-path examples
checkov -d modules --framework terraform
checkov -d envs --framework terraform
```

## The wrong application environment is selected

`envs/apps` is keyed by Terraform Cloud workspace, not by directory name.

Always verify the workspace before planning:

```bash
echo "$TF_WORKSPACE"
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=../../examples/dev.tfvars
```

## `envs/apps` cannot find the organization remote state

By default, `envs/apps` reads outputs from the Terraform Cloud workspace named `organization`.

Verify:

- `tfc_organization` is correct
- `organization_workspace_name` is still `organization`, unless intentionally overridden
- the `organization` workspace has already been applied

## Release tags do not trigger

The release-metadata workflow only listens for:

```text
organization/vX.Y.Z
apps/<env>/vX.Y.Z
```

Examples:

```bash
git tag -a organization/v1.0.0 -m "Organization v1.0.0"
git push origin organization/v1.0.0

git tag -a apps/dev/v1.0.0 -m "Apps dev v1.0.0"
git push origin apps/dev/v1.0.0
```

Those tags publish release metadata after a successful Terraform Cloud run. They do not perform a live apply.

## Pre-commit hooks fail because `core.hooksPath` is set

```bash
git config --unset core.hooksPath
make pre-commit-install
```

## Need more detail from Terraform

```bash
export TF_LOG=DEBUG
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=../../examples/dev.tfvars
```

## WIF / ADC authentication failures in CI

Workload Identity Federation is configured in `modules/stages/bootstrap`. If a GitHub Actions job fails with `google: could not find default credentials` or `Permission denied on resource project`:

1. Confirm the WIF pool and provider were created:

   ```bash
   gcloud iam workload-identity-pools list --location=global --project=<bootstrap-project>
   ```

2. Confirm the service account impersonation binding exists:

   ```bash
   gcloud iam service-accounts get-iam-policy <sa>@<project>.iam.gserviceaccount.com \
     --flatten="bindings[].members" --filter="bindings.role:roles/iam.workloadIdentityUser"
   ```

3. Check the subject attribute in the workflow against the binding condition — it must match `attribute.repository/<org>/<repo>`. The attribute values come from GitHub's OIDC token claims.

4. If using `google-github-actions/auth`, confirm `workload_identity_provider` is the full provider resource name (`projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`), not the pool name. The `github_oidc_provider_name` output from `envs/organization` exposes this value.

For local ADC issues (`gcloud auth application-default login` expired), refresh credentials:

```bash
gcloud auth application-default login --scopes=https://www.googleapis.com/auth/cloud-platform
```

## `terraform test` fails or produces no output

`terraform test` requires Terraform ≥ 1.7 for `mock_provider` support. Verify:

```bash
terraform version
```

If tests are silently skipped:

- Check that test files end in `.tftest.hcl` (not `.tf` or `.tftest`)
- Confirm `terraform init -backend=false` succeeds in the module directory first
- Run with `-verbose` to see individual assertion values:

  ```bash
  terraform test -verbose
  ```

If a test fails with `Provider requires explicit configuration`:

- Add `mock_provider "<provider-name>" {}` to the test file for every provider in `versions.tf`
- Re-check `versions.tf` for transitive providers (e.g., `google-beta` pulled in by child modules)

If an acceptance test fails due to data source postconditions in deeply nested modules:

- Use `override_module` blocks (Terraform ≥ 1.9) to bypass child module evaluation:

  ```hcl
  override_module {
    target  = module.child
    outputs = { self_link = "projects/mock/global/networks/mock-vpc" }
  }
  ```

## tfsec or Checkov reports a false positive

Inline skips are the correct fix. Do not add findings to the global skip list in `security-scan.yml` — that silences the check for all future resources.

**tfsec inline skip:**

```hcl
resource "google_storage_bucket" "example" {
  #tfsec:ignore:google-storage-bucket-encryption-customer-key
  name = "example"
}
```

**Checkov inline skip:**

```hcl
resource "google_storage_bucket" "example" {
  # checkov:skip=CKV_GCP_62:Bucket is intentionally public for static website hosting
  name = "example"
}
```

Always include a justification after the colon. The CI Checkov run uses `.checkov.yaml` for repo-level exceptions; add an entry there only if the skip applies to every instance of that check across the entire codebase.

---

## Plan-time precondition failures

### `Error: Resource precondition failed — subnet CIDR count guard`

```text
╷
│ Error: Resource precondition failed
│ on modules/host/main.tf: Each non-empty subnet_cidrs list must have at least
│ as many entries as availability zones in the region. Detected 3 zones;
│ provided public=0, private=2, database=0 CIDRs. Either add CIDRs or leave
│ the list empty to use auto-generated values.
```

**Cause:** `modules/host` takes subnet CIDRs as a single `subnet_cidrs` object with `public`/`private`/`database` list keys (not separate `private_subnet_cidrs`/`database_subnet_cidrs` variables). If you supply a non-empty list for one of those keys, it must have at least one CIDR per availability zone in the region.

**Fix (option A — recommended for production):** Set `explicit_zones` to pin the exact zones you need:

```hcl
explicit_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
```

Then supply one CIDR per zone for each tier you override:

```hcl
subnet_cidrs = {
  public   = []
  private  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  database = []
}
```

**Fix (option B):** Add CIDRs until each non-empty list's count matches or exceeds the zone count returned by the region, or leave a tier's list empty (`[]`) to fall back to auto-generated CIDRs.

---

### `Error: Resource precondition failed — deletion protection guard`

```text
╷
│ Error: Resource precondition failed
│ on modules/host/main.tf: set enable_deletion_protection = false and re-apply
│ before running terraform destroy.
```

**Cause:** `enable_deletion_protection = true` (the default) blocks `terraform destroy` of the hub network stack.

**Fix:** Set `enable_deletion_protection = false` and apply once before destroying:

```hcl
enable_deletion_protection = false
```

```bash
terraform apply   # lifts the guard
terraform destroy # now succeeds
```

---

## VPC-SC `projects/` membership errors

### `Error: Error creating Service Perimeter … "projects/my-project-id" is not a valid resource name`

**Cause:** The `modules/network/vpc-sc` module's `protected_projects` variable (and the `resources`/`sources[].resource` fields inside `vpc_sc_ingress_policies`/`vpc_sc_egress_policies` at the `envs/apps` root) require **numeric project numbers**, not project ID strings. The Access Context Manager API only accepts the `projects/<number>` form, and the module prepends the `projects/` prefix automatically — do not include it yourself.

**Fix:** Replace project ID strings with numeric project numbers:

```bash
gcloud projects describe my-project-id --format='value(projectNumber)'
```

Then set (e.g. in a custom `vpc_sc_ingress_policies` entry, `envs/apps` tfvars):

```hcl
vpc_sc_ingress_policies = [
  {
    sources = [
      { resource = "123456789012" }   # numeric project number, not project ID, and no "projects/" prefix
    ]
    resources = ["projects/123456789012"]
  }
]
```

`envs/apps` itself already resolves and protects its own host project number automatically (`data.google_project.host_project.number` in `envs/apps/main.tf`) — you only need to supply numbers manually when referencing **other** (spoke) projects in custom ingress/egress policies.

---

## Previously-reported bugs fixed in recent releases

The following errors were present in earlier versions and have been resolved. If you encounter them on an older revision, upgrade to the latest release.

| Symptom | Root cause | Fixed in |
|---------|------------|----------|
| `google_cloud_run_service_iam_member: resource not found` on budget notifier deploy | Cloud Functions gen2 deploys as Cloud Run v2; the wrong IAM resource type was used | Round 28 |
| `Error: Invalid combination of arguments: enforce_on_key and enforce_on_key_configs are mutually exclusive` | Cloud Armor rate limit rule set both fields | Round 28 |
| VPC-SC `permission denied` with project ID string (see above) | `spoke_project_ids` accepted strings; API requires numbers | Round 28 |

---

## AWS

### `terraform validate` fails with "Provider configuration not present"

```text
╷
│ Error: Provider configuration not present
│ To use module.example.aws_… its original provider configuration at
│ provider["registry.terraform.io/hashicorp/aws"].management is required…
```

**Cause:** Cross-account AWS modules declare `configuration_aliases` (e.g. `aws.management`, `aws.log_archive`) so the caller must pass in per-account providers. Such a module has **no provider of its own** and therefore cannot be `terraform validate`d standalone — this error is expected, not a bug.

**Fix:** Validate via the module's `examples/` root or the composing root (`envs/aws-*`), which supply the aliased providers. CI already skips these modules in the standalone validate step for the same reason.

---

### CloudTrail / Config / SNS fails with `KMSAccessDenied`

```text
╷
│ Error: … KMSAccessDenied: The ciphertext refers to a customer master key
│ that does not exist, does not exist in this region, or you are not allowed
│ to access.
```

**Cause:** A service running in one account (CloudTrail, Config, an SNS topic) is trying to use a CMK whose **key policy** does not grant that service's principal. A CMK is account- and Region-scoped; a cross-account service principal has no access unless the key policy explicitly allows it.

**Fix:** Either use a CMK in the **consuming** account, or grant the service principal in the key policy scoped by `aws:SourceOrgID` (org-wide) rather than a broad `kms:ViaService` grant. See the KMS-grant note in [CLAUDE.md → AWS modules](../../CLAUDE.md).

---

### `tflint --init` fails with a GitHub `403` rate limit

```text
Failed to install a plugin; … 403 API rate limit exceeded
```

**Cause:** `tflint --init` downloads ruleset plugins from GitHub releases; unauthenticated requests hit the anonymous rate limit, especially in CI.

**Fix:** Export a token before running the install:

```bash
export GITHUB_TOKEN="<a token with public_repo / read access>"
tflint --init
```

---

### `terraform destroy` cannot delete an Object Lock (COMPLIANCE) bucket

**Cause:** The Log Archive bucket is created with S3 Object Lock in **COMPLIANCE** mode (WORM). Objects — and the bucket — cannot be deleted within the retention window by anyone, including the account root. This is intended immutability, not a permissions failure.

**Fix:** There is no override. Wait out the retention window, or (for a genuine teardown) follow the [`aws-teardown.md`](../runbooks/aws-teardown.md) runbook.

---

### `account_role_arns["<key>"]` fails at plan when applying `aws-workload`

```text
╷
│ Error: Invalid index
│ The given key does not identify an element in this collection value.
```

**Cause:** A downstream root (typically `aws-workload`) resolved `account_role_arns[<key>]` from the `aws-organization` remote state, but that account was never added to the org. `account_role_arns` only contains keys for accounts declared in the org root's `workload_accounts` (and `accounts`) map.

**Fix:** Add the workload account to `envs/aws-organization` under `workload_accounts`, apply `aws-organization` first so it vends the account and republishes `account_role_arns`, then apply `aws-workload`. See [`aws-add-account.md`](../runbooks/aws-add-account.md).

---

## Supabase module errors

### `Error: supabase: Tenant or user not found`

```text
╷
│ Error: supabase: Tenant or user not found
```

**Cause:** `SUPABASE_ACCESS_TOKEN` is not set, expired, or lacks the **Manage organization** scope. The provider uses this token for all Management API calls; without it, every resource read returns a 404-like error instead of a 401.

**Fix:** Regenerate the token at [https://app.supabase.com/account/tokens](https://app.supabase.com/account/tokens) and export it:

```bash
export SUPABASE_ACCESS_TOKEN="sbp_your_new_token_here"
terraform init   # re-initialise if the provider was not previously installed
terraform plan
```

---

### `Error: Missing required argument: VERCEL_API_TOKEN`

```text
╷
│ Error: Missing required argument
│ The argument "api_token" is required, but no definition was found.
```

Or from the provider itself:

```text
╷
│ Error: vercel: 403 Forbidden — API token not found
```

**Cause:** `VERCEL_API_TOKEN` is not set. The Vercel provider reads the token from the environment variable. This error appears even when `enable_vercel = false` if the calling root declares the Vercel provider in `required_providers` (e.g. when calling `modules/stages/saas-workload`).

**Fix:** Export the token before running any Terraform command in that root:

```bash
export VERCEL_API_TOKEN="your_vercel_token_here"
```

To use Supabase without the Vercel provider requirement, call `modules/supabase/environment` directly instead of `modules/stages/saas-workload`. The primitive modules have no Vercel provider declaration.

---

### Node.js not found / vault-secrets provisioner fails

```text
╷
│ Error: local-exec provisioner error
│ Error running command: exec: "node": executable file not found in $PATH
```

Or:

```text
╷
│ Error: local-exec provisioner error
│ Error running command 'node scripts/bootstrap.mjs': exit status 1
│ Cannot find module 'pg'
```

**Cause (first error):** Node.js is not installed or not on `$PATH`. The vault-secrets module runs `node scripts/bootstrap.mjs` and `node scripts/reconcile.mjs`. Node.js >= 18 is required.

**Fix:** Install Node.js (use `nvm`, `mise`, `brew install node`, or the official installer), then verify:

```bash
node --version   # must report v18.x or higher
```

**Cause (second error):** `npm install` has not been run in the scripts directory — the `pg` package is missing.

**Fix:**

```bash
cd modules/supabase/vault-secrets/scripts
npm install
cd -
terraform apply
```

Re-run `npm install` after a fresh clone; `scripts/node_modules/` is gitignored.

---

### Vault safety guard refuses to wipe secrets

```text
╷
│ Error: local-exec provisioner error
│ SAFETY_GUARD: desired secret set is empty but vault already contains N IaC-managed
│ secrets. set VAULT_ALLOW_EMPTY_DESIRED=1 in the apply environment.
```

**Cause:** `var.secrets` was set to an empty map `{}` while the Supabase Vault still contains secrets written by a previous apply. The safety guard blocks this to prevent accidental data loss — a blank `secrets = {}` is more often a misconfiguration than an intentional delete-all.

**Fix (to delete all secrets intentionally):** Set the `VAULT_ALLOW_EMPTY_DESIRED` environment variable to `1` before applying:

```bash
export VAULT_ALLOW_EMPTY_DESIRED=1
terraform apply
unset VAULT_ALLOW_EMPTY_DESIRED
```

**Fix (to preserve existing secrets and remove the error):** Restore the desired secrets map to include all currently-managed keys. The Vault is the source of truth for which keys exist; inspect via the Supabase dashboard or by connecting directly to the database.

> **Scope note:** The safety guard and the reconcile script only manage secrets whose keys match `^[A-Z][A-Z0-9_]*$` (UPPER_SNAKE_CASE). Secrets created outside Terraform with lowercase or mixed-case names are not touched by `terraform apply` or `terraform destroy`.
