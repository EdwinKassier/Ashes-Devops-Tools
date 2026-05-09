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
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=examples/dev.tfvars
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
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=examples/dev.tfvars
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

```
╷
│ Error: Resource precondition failed
│ on modules/host/main.tf: var.private_subnet_cidrs has fewer entries than the
│ number of zones in the selected region.
```

**Cause:** The number of CIDR blocks supplied for `private_subnet_cidrs` (or `database_subnet_cidrs`) is less than the number of availability zones `modules/host` will create subnets in.

**Fix (option A — recommended for production):** Set `explicit_zones` to pin the exact zones you need:
```hcl
explicit_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
```
Then add one CIDR per zone:
```hcl
private_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
```

**Fix (option B):** Add CIDRs until the count matches or exceeds the zone count returned by the region.

---

### `Error: Resource precondition failed — deletion protection guard`

```
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

**Cause:** `spoke_project_numbers` was given a project ID string instead of a numeric project number. The Access Context Manager API only accepts the `projects/<number>` form.

**Fix:** Replace project ID strings with numeric project numbers:
```bash
gcloud projects describe my-project-id --format='value(projectNumber)'
```
Then set:
```hcl
spoke_project_numbers = {
  "my-project" = "123456789012"   # numeric number, not project ID
}
```

---

## Previously-reported bugs fixed in recent releases

The following errors were present in earlier versions and have been resolved. If you encounter them on an older revision, upgrade to the latest release.

| Symptom | Root cause | Fixed in |
|---------|------------|----------|
| `google_cloud_run_service_iam_member: resource not found` on budget notifier deploy | Cloud Functions gen2 deploys as Cloud Run v2; the wrong IAM resource type was used | Round 28 |
| `Error: Invalid combination of arguments: enforce_on_key and enforce_on_key_configs are mutually exclusive` | Cloud Armor rate limit rule set both fields | Round 28 |
| VPC-SC `permission denied` with project ID string (see above) | `spoke_project_ids` accepted strings; API requires numbers | Round 28 |
