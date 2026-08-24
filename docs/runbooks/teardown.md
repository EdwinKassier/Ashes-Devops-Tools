# Runbook: GCP Landing Zone Teardown

**When to use:** You are decommissioning some or all of the GCP landing zone — a single workload environment, or the whole organization control plane. This is the reverse of the stand-up in [`gcp-landing-zone.md`](../architecture/gcp-landing-zone.md), and it carries hard, **intended** immutability caveats that mean a full clean `terraform destroy` is often impossible without deliberate code changes and long waits.

**Time:** Minutes-to-hours per root for the destroyable parts; the immutable parts (CMEK keys pending destruction, retained audit logs) cannot be cleared until their windows elapse — potentially **days to years**.
**Risk:** Very high and largely irreversible. Data encrypted with a destroyed CMEK key is unrecoverable; foundation projects and folders are guarded against deletion by design. Read this entire runbook before running any `destroy`.
**Prerequisites:** You understand the root inventory in [`provider-selection.md`](../architecture/provider-selection.md) and have destroy-capable access to each Terraform Cloud workspace. Confirm no other environment depends on shared resources you are about to remove.

---

> **Do not run a blind `terraform destroy` across roots.** There is no cross-root `depends_on`; ordering is your responsibility. `envs/gcp/workload` reads `envs/gcp/organization`'s remote state (`data.terraform_remote_state.organization`) and peers its host VPC to the org's network hub, so destroying the organization root while any workload workspace still references it leaves orphaned resources and failed destroys.

---

## Reverse-order destroy

Destroy in the **exact reverse** of the stand-up order. Every workload environment must be fully destroyed before the organization control plane:

```text
2. gcp-workload-<env>   (per env — destroy EVERY workload workspace first)
1. gcp-organization     (last — folders, projects, KMS, network hub, audit sinks)
```

Why this order:

- **Remote-state dependency.** `envs/gcp/workload/main.tf` reads `data.terraform_remote_state.organization` for `environment_config`, `admin_project_number`, `hub_network`, and `billing_account`. Destroy the organization root first and every workload plan breaks.
- **Shared VPC / peering ordering.** Each workload attaches its host project to the org hub network (VPC peering + DNS peering against `hub_network.vpc_self_link`). Service-project attachments and peerings must be torn down before the hub VPC they point at, or the hub destroy fails with dependent-resource errors.

The `saas` root (Supabase/Vercel) is independent of the GCP chain — destroy it whenever; it holds no GCP resources.

For each root, apply the destroy through its Terraform Cloud workspace (never `terraform apply`/`destroy` locally against these roots — see [`../../CLAUDE.md`](../../CLAUDE.md#state--apply-rules)):

```bash
export TF_WORKSPACE=gcp-workload-<env>   # repeat for every workload env
terraform -chdir=envs/gcp/workload plan -destroy   # review; run the destroy via TFC
```

---

## The deletion-protection wall

Several foundation resources are deliberately guarded so a routine plan can never destroy them. Terraform will **refuse to plan** their destruction until you relax the guard **in code (or state) and apply first**. There is no runtime flag that lets `destroy` blow past these — that is the point.

### `prevent_destroy` lifecycle guards

| Resource | Location |
|----------|----------|
| Org OU folders (`google_folder.ou_folders`) | [`modules/gcp/iam/organization/main.tf`](../../modules/gcp/iam/organization/main.tf#L43) |
| KMS CryptoKeys (`google_kms_crypto_key.keys`) | [`modules/gcp/governance/kms/main.tf`](../../modules/gcp/governance/kms/main.tf#L30) |
| Billing-export BigQuery dataset | [`modules/gcp/stages/organization/main.tf`](../../modules/gcp/stages/organization/main.tf#L332) |

`prevent_destroy = true` is a **static compile-time literal** — it cannot be toggled with a variable. To get past it you must either:

1. **Edit the module** to remove (or comment out) the `lifecycle { prevent_destroy = true }` block, then apply, then destroy; or
2. **Remove the resource from state** (`terraform state rm <address>`) and delete it out-of-band in the GCP console/`gcloud`.

For the billing-export dataset specifically, the in-code note is explicit: BigQuery datasets with tables **are** destroyed by `terraform destroy` once the guard is gone, so manually delete the tables first if you want to preserve billing history.

### `enable_deletion_protection` sentinels (toggle-able)

Newer network modules implement the same protection through a conditional `terraform_data` sentinel that carries the static `prevent_destroy`, but is **created only when the flag is true** — so you can disable it via a variable and one apply, no state surgery:

| Resource / stage | Flag default | Location |
|------------------|--------------|----------|
| VPC-SC perimeters | `enable_deletion_protection = true` | [`modules/gcp/network/vpc-sc`](../../modules/gcp/network/vpc-sc/main.tf#L20) |
| Network hub + DNS VPC | `enable_deletion_protection = true` | [`modules/gcp/stages/network-hub`](../../modules/gcp/stages/network-hub/main.tf) |
| Host-project VPC/subnet stack | `enable_deletion_protection = false` | [`modules/gcp/stages/host`](../../modules/gcp/stages/host/main.tf#L55) |
| Standalone VPC module | `enable_deletion_protection = false` | [`modules/gcp/network/vpc`](../../modules/gcp/network/vpc/main.tf#L15) |

Teardown sequence for these:

1. Set `enable_deletion_protection = false` and **apply** (this removes the sentinel).
2. Run the `destroy` in a second apply.

If you cannot re-apply first (e.g. the config is already partly gone), fall back to removing the sentinel from state, exactly as documented in each module's variable description:

```bash
terraform state rm '<module_address>.terraform_data.deletion_protection_guard[0]'
```

### `deletion_policy = "PREVENT"` on foundation projects

The admin/automation project and every environment project are created with `deletion_policy = "PREVENT"`, so `terraform destroy` will not close them:

- Admin project — [`modules/gcp/stages/bootstrap/main.tf`](../../modules/gcp/stages/bootstrap/main.tf#L28)
- Environment projects — [`modules/gcp/stages/projects/main.tf`](../../modules/gcp/stages/projects/main.tf#L43)

To actually delete them, change `deletion_policy` to `"ABANDON"` (or `"DELETE"`) in the module and apply, then destroy — or remove them from state and close them by hand. Closing a GCP project moves it to a **~30-day pending-deletion** state before permanent removal; it can be restored within that window.

---

## KMS caveat — keys schedule for destruction, keyrings are forever

This is the GCP analog of AWS Vault Lock: some cryptographic state simply cannot be hard-deleted by Terraform.

The CMEK module ([`modules/gcp/governance/kms`](../../modules/gcp/governance/kms/main.tf)) creates a `google_kms_key_ring` and one or more `google_kms_crypto_key` resources.

- **CryptoKeys cannot be deleted — only *scheduled for destruction*.** After you clear the `prevent_destroy` guard, destroying a key merely moves its active versions into a `DESTROY_SCHEDULED` state for a pending window (GCP default **24 hours**; configurable, and commonly set to as long as 30 days). During that window the key version can be *restored*. Only after the window elapses is key material actually erased.
- **Keyrings are never deleted.** `google_kms_key_ring` has no delete operation in the GCP API — a keyring (and the tombstones of its destroyed keys) **persists in the project forever**. Terraform simply drops it from state; the keyring stays.
- **Data encrypted with a destroyed key is unrecoverable.** Once a key version is destroyed (window elapsed), anything encrypted under it — including the audit-log bucket, BigQuery datasets, or any CMEK-encrypted resource that used it — can never be decrypted. Confirm nothing you still need depends on the key *before* scheduling destruction.

Because keyrings persist, you cannot ever return a KMS-bearing project to a truly pristine state. Plan to either leave the project in place or close it (pending-deletion window) rather than expecting a clean KMS teardown.

---

## Audit-log caveat — logs are retained by design

The Cloud Audit Logs module ([`modules/gcp/governance/cloud-audit-logs`](../../modules/gcp/governance/cloud-audit-logs/main.tf)) stands up the audit-log GCS bucket, its access-log bucket, and org/project log sinks. It is built to keep logs, not shed them:

- Both buckets have **object versioning enabled** and a **lifecycle rule** that deletes objects only after `log_retention_days`.
- `force_destroy` is wired to `var.force_destroy_bucket`, which **defaults to `false`** — so `terraform destroy` will **refuse to delete a non-empty bucket**. Every current object *and every non-current (versioned) object* must be cleared first.
- The bucket is intentionally **not** locked with a `retention_policy { locked = true }` (see the in-code rationale), so retention here is operator-controlled rather than WORM — but the sinks (`google_logging_organization_sink`, `google_logging_project_sink`) keep streaming new objects in until you remove them.

**Recommendation: preserve audit logs for compliance.** Do not set `force_destroy_bucket = true` reflexively. The correct decommission order is:

1. Remove/disable the org and project log sinks first (stop new writes).
2. Export or archive the logs you must retain for compliance.
3. Only then clear objects + versions and set `force_destroy_bucket = true` (or empty the bucket out-of-band) so the bucket can be destroyed.

---

## Billing, org policies, and other control-plane cleanup

- **Billing.** Closing the foundation projects (via `deletion_policy`, above) unlinks them from the billing account as they enter pending-deletion. The billing account itself and its linkage to the organization are **not** managed for deletion by these roots — unlink or close it out-of-band if required.
- **Org policies & IAM.** Organization-level policies, `google_organization_iam_member` bindings, and the org audit config are non-authoritative / additive; destroying the organization root removes the ones Terraform created but leaves pre-existing org state intact.
- **Liens.** This landing zone does **not** create `google_resource_manager_lien` resources. If a lien was placed out-of-band on a project, `terraform destroy` and project closure will both fail until the lien is removed manually (`gcloud resource-manager liens delete <lien>`).

---

## Out-of-band leftovers (not destroyed by Terraform)

`terraform destroy` will **not** remove any of the following — clean them up manually only if you truly mean to:

- The **GCP Organization** itself and the **Cloud Identity / Workspace domain** it is bound to.
- The **billing account**.
- **KMS keyrings** (and destroyed-key tombstones) — permanent, see the KMS caveat.
- The **Terraform Cloud workspaces** and their remote state — delete these in TFC after the roots are torn down.
- Anything created by the out-of-band phase-0 bootstrap that predates the runnable `gcp-organization` workspace.

---

## Safety & confirmation

- **Read the whole runbook first.** The destroy is largely irreversible; there is no undo for a destroyed key version once its window elapses.
- **Confirm no cross-environment dependents.** Verify no other workload workspace still reads the organization root or peers with the hub before you touch shared resources.
- **Always `plan -destroy` and review before applying.** Run the destroy through Terraform Cloud, read the full plan, and confirm the resource list matches your intent — especially that you are not about to schedule a KMS key you still need or force-destroy a compliance log bucket.
- **Relax guards deliberately, one at a time.** Flip `enable_deletion_protection`/`deletion_policy` (or remove `prevent_destroy`) as its own reviewed change, apply, and only then destroy. Do not batch guard-removal with the destroy in a single blind run.
- **Prefer close-over-delete for projects** so they sit in the ~30-day pending-deletion window (restorable) rather than being lost.

---

## See also

- [AWS Landing Zone Teardown](aws-teardown.md) — the AWS counterpart to this runbook.
- [GCP Landing Zone](../architecture/gcp-landing-zone.md) — the architecture this reverses.
- [KMS Rotation](kms-rotation.md) — CMEK key lifecycle and rotation context.
