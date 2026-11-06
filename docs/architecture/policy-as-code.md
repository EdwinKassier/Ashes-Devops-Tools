# Policy as code (HCP Terraform OPA)

`policies/opa/` is an HCP Terraform **OPA policy set**. It checks every plan
against landing-zone guardrails before apply. It runs alongside the static scanners
(Trivy, Checkov), not instead of them. The scanners read HCL. The policy set reads
the rendered plan, so it sees values that come out of modules, `for_each` and
variables. It also sees what a run is about to destroy.

## How it is wired

`envs/tfc-admin` creates `tfe_policy_set.opa` when `enable_policy_sets = true`:

- `kind = "opa"`, `policies_path = "policies/opa"`, sourced from `var.vcs_repo`
  (required). The set is attached to every workspace that `tfc-admin` manages.
- `overridable = true`: users with **Manage Policy Overrides** can override a
  failed mandatory policy on a run.
- `policy_tool_version = var.opa_version` (null = the HCP Terraform default).
  The policies use Rego v1 syntax and keep `import rego.v1`, so they parse on
  OPA 0.59+ and on 1.x. Pin `opa_version` to the version you test with.
- HCP Terraform Free allows one policy set of up to five policies. This set
  declares ten, so it needs Standard or Premium.

To enable it, set `enable_policy_sets = true` and `vcs_repo` in the `tfc-admin`
workspace, then apply `tfc-admin` (through HCP Terraform, as for every root).

## Input document

HCP Terraform passes OPA one document. `input.plan` is the JSON plan (the
`terraform show -json` shape) and `input.run` holds run metadata (organization,
workspace and similar). The policies read only
`input.plan.resource_changes[]`:

| Field | Meaning |
|---|---|
| `address`, `module_address`, `mode`, `type`, `name` | Resource identity. `mode == "data"` entries are ignored. |
| `change.actions` | `["create"]`, `["update"]`, `["delete"]`, `["no-op"]`, or a replace (`["delete","create"]` / `["create","delete"]`). |
| `change.before` / `change.after` | Planned values. Nested blocks show up as lists (`settings[0].ip_configuration[0]`). |
| `change.after_unknown` | `true` for values that are only known after apply. Policies **skip** unknown values instead of failing on them. |

Shared helpers (`writes`, `creates`, `deletes`, `known_and_not`, policy-JSON
decoding) are in `policies/opa/lib_helpers.rego` (`package terraform.lib`). A policy
query can evaluate code from several `.rego` files.

## Policies and enforcement levels

`policies/opa/policies.hcl` declares one `policy` block per query. Each query
returns a set of messages, and an empty set means the policy passed.

- **mandatory**: a violation stops the run. A user with override permission can
  still override it.
- **advisory**: the violation shows on the run but never blocks it.

| Policy | Level | Rule |
|---|---|---|
| `gcs_no_public_buckets` | mandatory | `google_storage_bucket` sets `uniform_bucket_level_access = true` and `public_access_prevention = "enforced"`. |
| `gcp_iam_no_public_members` | mandatory | No `allUsers` / `allAuthenticatedUsers` in any `google_*_iam_member`, `_iam_binding` or `_iam_policy` (`policy_data`). |
| `aws_s3_public_access` | mandatory | No `public-read` / `public-read-write` / `authenticated-read` canned ACL. Every bucket- and account-level public access block keeps all four switches `true`. |
| `aws_sg_no_public_admin_ports` | mandatory | No ingress from `0.0.0.0/0` or `::/0` that reaches TCP 22 or 3389, including all-protocol (`-1`) rules. Covers `aws_security_group`, `aws_security_group_rule` and `aws_vpc_security_group_ingress_rule`. |
| `aws_iam_no_admin_wildcard` | mandatory | No `Allow` statement with `Action "*"` on `Resource "*"` in `aws_iam_policy`, `aws_iam_{role,user,group}_policy` or `aws_iam_role.inline_policy`. `Deny` statements are fine (break-glass deny-all). |
| `aws_kms_key_rotation` | mandatory | Symmetric `aws_kms_key` sets `enable_key_rotation = true`. Asymmetric and HMAC keys are exempt. |
| `database_private_encrypted` | mandatory | `google_sql_database_instance` sets `ipv4_enabled = false`, and a missing `ip_configuration` block counts as public. `aws_db_instance` / `aws_rds_cluster` set `storage_encrypted = true`. `aws_db_instance` / `aws_rds_cluster_instance` are not `publicly_accessible`. |
| `aws_s3_bucket_public_access_block_present` | advisory | A new `aws_s3_bucket` has a public access block created in the same module instance, or an account-level block is in the plan. The pairing goes by module and count, because the bucket id is unknown at plan time. |
| `require_labels` | advisory | Listed GCP types carry at least one label (or `effective_labels`). Listed AWS types carry at least one tag (or `tags_all` from provider `default_tags`). |
| `destroy_guard` | advisory | Flags any delete or replace of KMS keys and key rings, log buckets, log sinks, CloudTrail, organisation policies, VPC-SC perimeters, and S3/GCS buckets whose name marks them as log or audit archives. |

The mandatory rules only encode controls that this repo's modules already meet
by default: hardened GCS buckets, private Cloud SQL, KMS rotation, private and
encrypted Aurora, no inline `*:*` Allow. Turning them on should not block an
existing workspace. Run `enable_policy_sets` in a non-production project first
and read the advisory results before relying on them.

## Adding a policy

1. Create `policies/opa/<name>.rego` with `package terraform.policies.<name>`,
   `import rego.v1` and `import data.terraform.lib`. Emit messages from a
   `deny contains msg if { ... }` rule, or from `warn` for an advisory companion
   query in the same package.
2. Filter with `lib.written_of_type("<type>")` (create/update/replace, managed
   only). Use `lib.known_and_not(rc, attr, want)` so that unknown values pass.
   Read optional attributes with `object.get`, never with a bare path that turns
   undefined.
3. Add `policies/opa/<name>_test.rego` with at least one passing and one failing
   fixture (`with input as {"plan": {"resource_changes": [...]}}`). Test files
   define no policy blocks and are never queried by HCP Terraform.
4. Add a `policy "<name>"` block to `policies.hcl`. Start at `advisory`, and
   promote it to `mandatory` once it runs clean across the estate.
5. Run the local checks below.

Do not put helpers in a `lib/` directory or in a file name that contains
`tfplan`: the repo `.gitignore` ignores both patterns.

## Local testing

Use the official OPA binary. Verify the download against the published
`.sha256` file:

```bash
V=v1.22.2
curl -sSLO "https://github.com/open-policy-agent/opa/releases/download/$V/opa_darwin_arm64_static"
curl -sSLO "https://github.com/open-policy-agent/opa/releases/download/$V/opa_darwin_arm64_static.sha256"
shasum -a 256 -c opa_darwin_arm64_static.sha256 && chmod +x opa_darwin_arm64_static

./opa_darwin_arm64_static check --strict policies/opa     # parse + strict lint
./opa_darwin_arm64_static fmt --fail -l policies/opa      # formatting
./opa_darwin_arm64_static test policies/opa -v            # unit tests
```

Or use Docker:
`docker run --rm -v "$PWD/policies:/p" openpolicyagent/opa:latest-static test /p -v`.

To run a policy against a real plan:

```bash
terraform plan -out=plan.bin && terraform show -json plan.bin > plan.json
jq '{plan: .}' plan.json > input.json
opa eval -d policies/opa -i input.json 'data.terraform.policies.destroy_guard.deny'
```

Keep `plan.json` and `input.json` out of git, because they hold planned values.
