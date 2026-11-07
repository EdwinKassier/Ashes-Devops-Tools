# Policy as code (HCP Terraform OPA)

`policies/opa/` and `policies/opa-destructive/` are HCP Terraform **OPA policy
sets**. They check every plan
against landing-zone guardrails before apply. It runs alongside the static scanners
(Trivy, Checkov), not instead of them. The scanners read HCL. The policy set reads
the rendered plan, so it sees values that come out of modules, `for_each` and
variables. It also sees what a run is about to destroy.

## How it is wired

`envs/tfc-admin` creates two sets, both `kind = "opa"`, sourced from `vcs_repo`
(required) and attached to every workspace that `tfc-admin` manages:

| Set | `policies_path` | Overridable | Contents |
|---|---|---|---|
| `tfe_policy_set.opa` (`<prefix>opa-guardrails`) | `policies/opa` | no (`policy_set_overridable`, default false) | 10 mandatory + 3 advisory guardrails |
| `tfe_policy_set.destructive` (`<prefix>destructive-change-guard`) | `policies/opa-destructive` | **yes**, always | the mandatory `destroy_guard` |

- A VCS policy set reads the `policies.hcl` in its own `policies_path`, so the
  destroy guard needs its own directory to be overridable while the guardrails
  stay hard gates. `policies/opa-destructive/lib_helpers.rego` is a copy of
  `policies/opa/lib_helpers.rego`; `make consistency` fails if they differ.
- **Overrides.** An intended destroy (decommissioning, a reviewed replace) is
  overridden on the run by the security team. An organization owner creates
  that team by hand, passes its ID to tfc-admin as `security_team_id` (as for
  `platform_team_id` and `control_plane_approvers_team_id`) and grants it
  **Manage Policy Overrides** in the HCP UI. That permission is org-wide.
  tfc-admin creates no teams and sets no organization access, so it still runs
  on a non-owner token; a check warns while the sets are on and
  `security_team_id` is null.
- `policy_tool_version = var.opa_version` (pinned). The policies use Rego v1
  syntax and keep `import rego.v1`, so they parse on OPA 0.59+ and on 1.x.
- **When they are on.** `enable_policy_sets = null` (the default) turns both
  sets on when `vcs_repo` (`org.tfc.vcs_repo`) is set **and** `org.tfc.plan`
  (tfc-admin `tfc_plan`) is `standard` or `premium`. HCP Terraform Free allows
  one policy set of up to five policies, so `free` and `essentials` stay off
  unless you set `enable_policy_sets = true` yourself. On Free that explicit
  `true` exceeds the limit (two sets, 14 policies): HCP Terraform rejects the
  second set or the extra policies, so do not set it there. Essentials support
  is unverified ([known gaps](../known-gaps.md)). While the sets are off,
  the `destructive_changes_guarded` check warns on every tfc-admin plan that
  destructive changes are unguarded. Drift on tiers without health assessments
  is caught by `.github/workflows/drift-detection.yml`, which fails rather than
  skips.

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
| `gcp_cloud_run_no_public_url` | mandatory | No `google_cloud_run_v2_service` with `invoker_iam_disabled = true` and `ingress = INGRESS_TRAFFIC_ALL` (an unauthenticated, unprotected run.app URL). Public apps use `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` behind the external ALB. |
| `aws_s3_public_access` | mandatory | No `public-read` / `public-read-write` / `authenticated-read` canned ACL. Every bucket- and account-level public access block keeps all four switches `true`. |
| `aws_sg_no_public_admin_ports` | mandatory | No ingress from `0.0.0.0/0` or `::/0` that reaches TCP 22 or 3389, including all-protocol (`-1`) rules. Covers `aws_security_group`, `aws_security_group_rule` and `aws_vpc_security_group_ingress_rule`. |
| `aws_iam_no_admin_wildcard` | mandatory | No `Allow` statement with `Action "*"`, or with any `NotAction`, on `Resource "*"` in `aws_iam_policy`, `aws_iam_{role,user,group}_policy` or `aws_iam_role.inline_policy`. `Deny` statements are fine (break-glass deny-all). |
| `aws_iam_federated_trust_pinned` | mandatory | Every `aws_iam_role` trust that allows `sts:AssumeRoleWithWebIdentity` from a federated provider must condition both `:aud` and `:sub`. The subject's tenant segment must be literal: no `*`, `organization:*:…` or `repo:*/…`. This blocks the "role trusting another TFC org / GitHub owner" persistence path at plan time. The RCP tenant pins are its runtime twin. |
| `gcp_no_basic_roles_high_scope` | mandatory | No `roles/owner` or `roles/editor` in `google_{organization,folder}_iam_{member,binding,policy}`. |
| `aws_kms_key_rotation` | mandatory | Symmetric `aws_kms_key` sets `enable_key_rotation = true`. Asymmetric and HMAC keys are exempt. |
| `database_private_encrypted` | mandatory | `google_sql_database_instance` sets `ipv4_enabled = false`, and a missing `ip_configuration` block counts as public. `aws_db_instance` / `aws_rds_cluster` set `storage_encrypted = true`. `aws_db_instance` / `aws_rds_cluster_instance` are not `publicly_accessible`. |
| `aws_s3_bucket_public_access_block_present` | advisory | A new `aws_s3_bucket` has a public access block created in the same module instance, or an account-level block is in the plan. The pairing goes by module and count, because the bucket id is unknown at plan time. |
| `require_labels` | advisory | Listed GCP types carry at least one label (or `effective_labels`). Listed AWS types carry at least one tag (or `tags_all` from provider `default_tags`). |
| `destroy_guard` | mandatory, **overridable** set (`policies/opa-destructive`) | Denies any delete or replace (either order) of a stateful type. GCP: `google_sql_database_instance`, `google_storage_bucket`, `google_kms_crypto_key`, `google_project`, `google_folder`, `google_compute_network`, `google_logging_organization_sink`, `google_logging_project_bucket_config`, `google_secret_manager_secret`. AWS: `aws_s3_bucket`, `aws_rds_cluster`, `aws_db_instance`, `aws_kms_key`, `aws_organizations_account`, `aws_dynamodb_table`, `aws_vpc`, `aws_cloudtrail`, `aws_secretsmanager_secret`, `aws_cloudformation_stack_set_instance` (a replace removes the recorders org-wide). Supabase: `supabase_project`. Plus key rings, the other log buckets/sinks, CloudTrail Lake, organisation policies and VPC-SC perimeters. The security team overrides an intended destroy. |

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

./opa_darwin_arm64_static check --strict policies/opa policies/opa-destructive
./opa_darwin_arm64_static fmt --fail -l policies/opa policies/opa-destructive
./opa_darwin_arm64_static test policies/opa policies/opa-destructive -v
```

Or use Docker:
`docker run --rm -v "$PWD/policies:/p" openpolicyagent/opa:latest-static test /p -v`.

To run a policy against a real plan:

```bash
terraform plan -out=plan.bin && terraform show -json plan.bin > plan.json
jq '{plan: .}' plan.json > input.json
opa eval -d policies/opa-destructive -i input.json 'data.terraform.policies.destroy_guard.deny'
```

Keep `plan.json` and `input.json` out of git, because they hold planned values.
A committed fixture must be scrubbed first:
`jq -f policies/opa/tests/fixtures/scrub.jq plan.json` keeps the resource
addresses, types, actions and the planned attributes the policies read, and
drops `before`, `after_sensitive` and identifiers. Review the output by eye
before committing it.
