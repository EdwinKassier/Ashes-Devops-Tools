# Self-Managed State (No HCP Terraform)

The roots under `envs/**` ship with a `cloud {}` block in `backend.tf`, so state, plans and runs live
in HCP Terraform (or Terraform Enterprise). If you cannot or do not want to use HCP Terraform, run
the same roots against a bucket you own. The Terraform code does not change; you add one untracked
override file per root and supply the cross-root values yourself.

> **Trade-off.** Without HCP Terraform you give up what `envs/tfc-admin` codifies: workspaces,
> run triggers, dynamic credentials, Sentinel/OPA policy sets, drift runs and team access. You own
> the pipeline that runs `terraform plan` and `apply`, the credentials it uses, and the review gate
> in front of the control-plane roots. The repo's rule against local `apply` on GCP roots exists
> because of that gate: replace it with your own CI job, not with a laptop.

## 1. Override the backend

Terraform merges `*_override.tf` files over the base configuration. An override `backend` block
**replaces** the `cloud` block, so no edit to `backend.tf` is needed. The repo's `.gitignore`
already ignores `*_override.tf`; keep the override out of the shared tree, or commit it deliberately
in a fork.

Templates (named `.example`, so Terraform never loads them from the template directory):

| Backend | Template |
|---|---|
| Google Cloud Storage | [`templates/backend/gcs_override.tf.example`](../../templates/backend/gcs_override.tf.example) |
| Amazon S3 | [`templates/backend/s3_override.tf.example`](../../templates/backend/s3_override.tf.example) |

```bash
cp templates/backend/gcs_override.tf.example envs/gcp/organization/backend_override.tf
$EDITOR envs/gcp/organization/backend_override.tf      # bucket + prefix
terraform -chdir=envs/gcp/organization init -reconfigure
```

Rules for the bucket:

- One state object per root: a distinct `prefix` (GCS) or `key` (S3), for example the old workspace
  name (`gcp-organization`, `aws-security`). For per-environment roots (`gcp-workload-<env>`,
  `aws-workload-<env>`) use one prefix or key per environment.
- Versioning on, public access blocked, encryption with a customer-managed key, and access limited
  to the pipeline identity. State contains secrets that are not write-only.
- Put the bucket in an account or project outside any estate it holds state for (the bootstrap
  admin project is the natural home on GCP). Do not store it in a project this repo can destroy.

## 2. Supply the upstream values

Roots normally read their upstream roots through `terraform_remote_state` against HCP Terraform
workspaces. That read fails without HCP Terraform, so supply each upstream's outputs through the
stage-contract variables. When a contract is set, the matching remote-state read is skipped
(`count = 0`) and the root plans without the upstream workspace.

| Root | Contract variables (config key `gcp.contracts.<layer>` / `aws.contracts.<layer>`) |
|---|---|
| `gcp/bootstrap` | none (phase 0, no upstream) |
| `gcp/organization` | `bootstrap_contract` |
| `gcp/guardrails` | none (by design it reads no remote state: it looks the organization and the `containment` tag up in GCP, so apply `gcp/organization` first) |
| `gcp/projects` | `bootstrap_contract`, `organization_contract` |
| `gcp/network-hub` | `organization_contract`, `projects_contract` |
| `gcp/workload` | `organization_contract`, `projects_contract`, `network_hub_contract` |
| `aws/organization` | none (first AWS root) |
| `aws/security`, `aws/network`, `aws/backup`, `aws/shared-services`, `aws/identity` | `organization_contract` |
| `aws/workload` | `organization_contract`, `network_contract`, `security_contract` |
| `saas/*`, `tfc-admin` | none (tfc-admin is not used without HCP Terraform) |

Fill them from the upstream root's `terraform output -json`, in a `*.auto.tfvars` file your pipeline
renders, or under `gcp.contracts` / `aws.contracts` in `config/landing-zone.yaml`. Each variable's
description lists the exact fields. Re-render the contract after every upstream apply; nothing
triggers the downstream root for you any more, so run the roots in the documented order
(see [bootstrap](../runbooks/bootstrap.md) and the [AWS bootstrap](../runbooks/aws-bootstrap.md)).

## 3. One HCP organization or project per estate

If you keep HCP Terraform for some roots, do not split one estate across several HCP organizations.
`tfc-admin` names its projects from `tfc.project_name_prefix`, and `aws_project` must equal the
project that the member-account OIDC trust expects (`tfc_project`). Use **one HCP organization (or
one prefixed project set) per estate**, and give a second estate its own organization or its own
`project_name_prefix`. Mixing self-managed and HCP-managed roots in one estate works only if every
cross-root read goes through a contract.

## 4. What does not work

- `envs/tfc-admin` has nothing to manage; do not apply it.
- Dynamic credentials (`TFC_*_PROVIDER_AUTH`) do not apply. Authenticate the pipeline with its own
  workload identity (GitHub OIDC to GCP WIF or an AWS role) and keep the credential out of state.
- Sentinel/OPA policy sets under `policies/` are enforced by HCP Terraform. Run the same rules in
  CI with `conftest` against `terraform show -json` output if you need them.

## 5. Migrating existing state

To move an estate off HCP Terraform, add the override, then run
`terraform init -migrate-state`. Terraform copies the current state from the `cloud` workspace into
the new backend. Do this one root at a time, in apply order, and confirm `terraform plan` shows no
changes before the next root.
