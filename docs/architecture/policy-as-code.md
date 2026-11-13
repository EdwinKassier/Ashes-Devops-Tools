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
| `tfe_policy_set.opa` (`<prefix>opa-guardrails`) | `policies/opa` | no (`policy_set_overridable`, default false) | 13 mandatory + 3 advisory guardrails |
| `tfe_policy_set.destructive` (`<prefix>destructive-change-guard`) | `policies/opa-destructive` | **yes**, always | the mandatory `destroy_guard`, `tfc_admin_guard` and `tfc_vcs_run_only` (PREVIEW) |

Both sets are also attached to the `tfc-admin` workspace itself, whether or
not it is self-managed (`manage_tfc_admin_workspace`): an unmanaged one is
looked up by name. So `tfc_admin_guard` judges the plan that would detach it.

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
  `true` exceeds the limit (two sets, 19 policies): HCP Terraform rejects the
  second set or the extra policies, so do not set it there. Essentials support
  is unverified ([known gaps](../known-gaps.md)). While the sets are off,
  the `destructive_changes_guarded` check warns on every tfc-admin plan that
  destructive changes are unguarded. Drift on tiers without health assessments
  is caught by `.github/workflows/drift-detection.yml`, which fails rather than
  skips.

## Input document

HCP Terraform passes OPA one document. `input.plan` is the JSON plan (the
`terraform show -json` shape) and `input.run` holds run metadata (organization,
workspace and similar). Every policy except `no_plan_time_code_execution`
and `tfc_vcs_run_only` reads only `input.plan.resource_changes[]`.
`tfc_vcs_run_only` reads only `input.run` (`speculative`, `commit_sha`,
`workspace.tags`, `workspace.vcs_repo`, the fields HCP Terraform documents in
[Terraform run data](https://developer.hashicorp.com/terraform/cloud-docs/policy-enforcement/define-policies/opa)).
It never reads `run.message`, which the API caller sets.
`no_plan_time_code_execution` reads `resource_changes[]` and also walks
`input.plan.configuration`: every module's resource blocks, their
`provisioners` and `mode`, the `source` of each module call, and
`provider_config` (one entry per provider configuration, including the implied
provider of each module, with its `full_name` and the argument names in
`expressions`). A provisioner or a data source never shows up as a resource
change that says so. It reads `resource_changes[].provider_name` and the
`backend` expression of each `terraform_remote_state` too. The configuration
JSON does not render a `dynamic` block inside a provider block or a `removed`
block, and it never shows environment variables or credential files, so the
policy cannot see what is set that way ([known gaps](../known-gaps.md)). The
`resource_changes[]` fields:

| Field | Meaning |
|---|---|
| `address`, `module_address`, `mode`, `type`, `name` | Resource identity. `mode == "data"` entries are ignored. |
| `change.actions` | `["create"]`, `["update"]`, `["delete"]`, `["no-op"]`, or a replace (`["delete","create"]` / `["create","delete"]`). |
| `change.before` / `change.after` | Planned values. Nested blocks show up as lists (`settings[0].ip_configuration[0]`). |
| `change.after_unknown` | `true` for values that are only known after apply. Mandatory policies deny an unknown value for the attribute they check (`lib.unknown_or_not`). Advisory policies may skip it. A value that is genuinely computed, such as a pool name that holds a new project number, is reported by an advisory rule instead. |

Shared helpers (`writes`, `creates`, `deletes`, `known_and_not`, `unknown_or_not`, policy-JSON
decoding) are in `policies/opa/lib_helpers.rego` (`package terraform.lib`). A policy
query can evaluate code from several `.rego` files.

## Policies and enforcement levels

`policies/opa/policies.hcl` declares one `policy` block per query. Each query
returns a set of messages, and an empty set means the policy passed.

- **mandatory**: a violation stops the run. A user with Manage Policy
  Overrides can override it only when its set is overridable: the
  `policies/opa` set only with `policy_set_overridable = true` (default
  `false`), the `policies/opa-destructive` set always.
- **advisory**: the violation shows on the run but never blocks it.

| Policy | Level | Rule |
|---|---|---|
| `gcs_no_public_buckets` | mandatory | `google_storage_bucket` sets `uniform_bucket_level_access = true` and `public_access_prevention = "enforced"`. |
| `gcp_iam_no_public_members` | mandatory | No `allUsers` / `allAuthenticatedUsers` in any `google_*_iam_member`, `_iam_binding` or `_iam_policy` (`policy_data`). |
| `no_plan_time_code_execution` | mandatory | Apply-time control for provisioners; detective control for the rest. HCP Terraform runs it after the plan, so a data source, a remote-state read or a provider binary has already run when it fails, and it stops the apply. Denies: a `provisioner` block anywhere except in resources declared directly in `module.saas_workload.module.vault_secrets`, reached through the exact call chain and source strings of `envs/saas` (`../../modules/saas/stages/saas-workload`, then `../../../supabase/vault-secrets`); a `data "external"`, `data "http"` or `data "aws_lambda_invocation"` block anywhere; an `action` block whose type is not on `allowed_action_types` (empty); a `data "terraform_remote_state"` whose `backend` is not the literal `cloud` or `remote` (a reference is denied too); a provider whose source address is not on `allowed_provider_sources` (the providers this repo declares, plus the built-in `terraform`), in `provider_config` or in `resource_changes[].provider_name`; a provider block that sets an endpoint, proxy or TLS key (`endpoints`, `*_endpoint` except `use_fips_endpoint`, `use_dualstack_endpoint` and `s3_us_east_1_regional_endpoint`, `hostname`, `base_url`, `api_url`, `metadata_host`, `universe_domain`, `custom_ca_bundle`, `insecure`, `ssl_skip_verify`, `skip_tls_verify`, `http_proxy`, `https_proxy`, `no_proxy`) or inline credentials (`credentials`, `token_url`). The allowlists are in `policies/opa/no_plan_time_code_execution_allowlist.rego`; a fork edits only that file. It cannot see a `removed` block (Terraform does not render it in the plan JSON), so a destroy-time provisioner there runs at apply unseen. The controls before the plan are `scripts/check-plan-time-exec.py` in CI (run by `scripts/check-consistency.sh`; it parses every `.tf` and `.tf.json` file of the repo and applies the lists of this policy, read from its `.rego` files, and also covers `removed` blocks, `dynamic` provider blocks and module sources) and `runs = read` for the platform team on secret-bearing projects (tfc-admin), which also keeps it from confirming an apply there. |
| `gcp_cloud_run_no_public_url` | mandatory | No `google_cloud_run_v2_service` with `invoker_iam_disabled = true` and `ingress = INGRESS_TRAFFIC_ALL` (an unauthenticated, unprotected run.app URL). Public apps use `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` behind the external ALB. |
| `aws_s3_public_access` | mandatory | No `public-read` / `public-read-write` / `authenticated-read` canned ACL. Every bucket- and account-level public access block keeps all four switches `true`. |
| `aws_sg_no_public_admin_ports` | mandatory | No ingress from `0.0.0.0/0` or `::/0` that reaches TCP 22 or 3389, including all-protocol (`-1`) rules. Covers `aws_security_group`, `aws_security_group_rule` and `aws_vpc_security_group_ingress_rule`. |
| `aws_iam_no_admin_wildcard` | mandatory | No `Allow` statement with `Action "*"`, or with any `NotAction`, on `Resource "*"` in `aws_iam_policy`, `aws_iam_{role,user,group}_policy` or `aws_iam_role.inline_policy`. `Deny` statements are fine (break-glass deny-all). |
| `aws_iam_federated_trust_pinned` | mandatory | Every `aws_iam_role` trust that allows `sts:AssumeRoleWithWebIdentity` from a federated provider must condition both `:aud` and `:sub`. The subject's tenant segment must be literal: no `*`, `organization:*:…` or `repo:*/…`. This blocks the "role trusting another TFC org / GitHub owner" persistence path at plan time. The RCP tenant pins are its runtime twin. |
| `gcp_wif_principalset_pinned` | mandatory | A workload identity `principalSet://iam.googleapis.com/.../workloadIdentityPools/<pool>/...` member in any `google_*_iam_member`, `_iam_binding` or `_iam_policy` (`policy_data`), for any role, must pin one repository and a ref or an environment. Denied: the whole pool (`/*`), `attribute.repository_owner_id/`, `attribute.repository/` (a mutable name, every branch) and `attribute.ref/` (that ref in every repository). The GitHub provider condition pins only the owner (`custom.wifProviderTenantPinned`), so each of these trusts every repository of the owner. A member that is unknown at plan time (a pool created in the same run) is not denied; the advisory rule reports it. |
| `tfc_vcs_run_only` | mandatory, **overridable** set (`policies/opa-destructive`), **PREVIEW** | A run that can apply (`run.speculative` is not `true`) on a VCS-connected workspace (`run.workspace.vcs_repo` is set) tagged `layer:control-plane`, `layer:bootstrap` or `tier:production` must carry a `run.commit_sha`. An API-uploaded configuration version has none, so an approver cannot upload unreviewed code and confirm it without a security-team override. Speculative plans, CLI-driven workspaces and plans without run data pass. The field is confirmed by the docs only, so the rule stays in the overridable set until a sandbox run confirms it ([known gaps](../known-gaps.md)). |
| `gcp_no_basic_roles_high_scope` | mandatory | No `roles/owner` or `roles/editor` in `google_{organization,folder}_iam_{member,binding,policy}`. |
| `aws_kms_key_rotation` | mandatory | Symmetric `aws_kms_key` sets `enable_key_rotation = true`. Asymmetric and HMAC keys are exempt. |
| `database_private_encrypted` | mandatory | `google_sql_database_instance` sets `ipv4_enabled = false`, and a missing `ip_configuration` block counts as public. `aws_db_instance` / `aws_rds_cluster` set `storage_encrypted = true`. `aws_db_instance` / `aws_rds_cluster_instance` are not `publicly_accessible`. |
| `aws_s3_bucket_public_access_block_present` | advisory | A new `aws_s3_bucket` has a public access block created in the same module instance, or an account-level block is in the plan. The pairing goes by module and count, because the bucket id is unknown at plan time. |
| `gcp_wif_principalset_repo_wide` | advisory | Reports a workload identity member bound on `attribute.repository_id/<id>` alone (every branch, tag and environment of the repository; `modules/gcp/iam/workload-identity` emits it for a binding with `repository_id` and an empty `github_allowed_refs`). Also reports an `iam_member` or `iam_binding` on `roles/iam.workloadIdentityUser` or `roles/iam.serviceAccountTokenCreator` whose member is unknown at plan time, and an `iam_policy` whose `policy_data` is unknown. |
| `require_labels` | mandatory | Listed GCP types carry the `managed-by`, `environment`, `cost-center` and `owner` labels (in `labels` or `effective_labels`, which holds the provider `default_labels`; Cloud SQL in `settings.user_labels`). Listed AWS types carry `ManagedBy`, `Environment`, `CostCenter` and `Owner` (in `tags` or `tags_all`, which holds the provider `default_tags`). Unlisted types, and types that cannot carry labels or tags, are not checked. An unknown label or tag map is skipped. |
| `destroy_guard` | mandatory, **overridable** set (`policies/opa-destructive`) | Denies any delete or replace (either order) of a stateful type. GCP: `google_sql_database_instance`, `google_storage_bucket`, `google_kms_crypto_key`, `google_project`, `google_folder`, `google_compute_network`, `google_logging_organization_sink`, `google_logging_project_bucket_config`, `google_secret_manager_secret`. AWS: `aws_s3_bucket`, `aws_rds_cluster`, `aws_db_instance`, `aws_kms_key`, `aws_organizations_account`, `aws_dynamodb_table`, `aws_vpc`, `aws_cloudtrail`, `aws_secretsmanager_secret`, `aws_cloudformation_stack_set_instance` (a replace removes the recorders org-wide). Supabase: `supabase_project`. Backups and immutability: `aws_backup_vault`, `aws_backup_vault_lock_configuration`, `aws_s3_bucket_object_lock_configuration`, `aws_efs_file_system`. Data and artefact stores: `google_bigquery_dataset`, `aws_ecr_repository`, `google_artifact_registry_repository`. DNS zones (a re-create changes the delegated name servers): `aws_route53_zone`, `google_dns_managed_zone`. Plus key rings, the other log buckets/sinks, CloudTrail Lake, organisation policies, VPC-SC perimeters, the admin-containment deny policies with their tag keys, values and bindings, and Transit Gateway attachments. The security team overrides an intended destroy. |
| `tfc_admin_guard` | mandatory, **overridable** set (`policies/opa-destructive`) | Guards the HCP Terraform layer that tfc-admin manages. Denies: deleting or replacing a `tfe_policy_set`, `tfe_workspace_policy_set` or `tfe_project_policy_set`; dropping a workspace from a set's `workspace_ids`; turning `global` off; changing `policies_path` or the `vcs_repo` identifier or branch; making a hard-gate set overridable; any `tfe_workspace_policy_set_exclusion`. Turning on `auto_apply` or `auto_apply_run_trigger` (also at creation) on a workspace tagged `layer:control-plane`, `layer:bootstrap` or `tier:production` (tfc-admin tags production workloads), or removing one of those tags. Widening team access: creating any `tfe_team_access`, `tfe_team_project_access`, team or organization membership or team/organization token, granting a team organization access, or raising a grant (fixed level, a custom permission, or fixed to custom by its nearest fixed level). Lowering access passes. Execution: setting `execution_mode` to `local` or `agent` on `tfe_workspace_settings` or `tfe_workspace` (a switch to `remote` passes), pointing a workspace at an agent pool, an unknown `execution_mode` (on `tfe_workspace`, on update only, because a create plans the deprecated attribute unknown), an unknown `agent_pool_id` when the mode is `agent` or unknown, and any write of `tfe_agent_pool`, `tfe_agent_token` or an agent pool allowed/excluded list. Wiring of a workspace tagged `layer:control-plane`, `layer:bootstrap` or `tier:production` (updates and replaces): a changed or unknown `vcs_repo` identifier, branch, OAuth token or GitHub App installation (removing `vcs_repo` too), `working_directory` or `project_id`. Env vars: a created `tfe_variable`, or one whose key, category, value or `value_wo_version` changes, with category `env` and a key that starts with `TFC_`, `TF_CLI_ARGS`, `TFE_` or `TF_TOKEN_`, or is one of the code-execution names tfc-admin refuses (`code_exec_env_pattern`; `scripts/check-env-pattern-sync.sh` keeps the two lists equal), and a written `tfe_variable` whose key or category is unknown. Variable sets: attaching (`tfe_workspace_variable_set`, `tfe_project_variable_set`) a set this configuration does not manage, an attachment whose set is unknown while no set is created in the plan, and a set made global. |

The mandatory rules only encode controls that this repo's modules already meet
by default: hardened GCS buckets, private Cloud SQL, KMS rotation, private and
encrypted Aurora, no inline `*:*` Allow. Each module sets the switches these
rules check (`uniform_bucket_level_access`, `public_access_prevention`, the four
public access block switches, `enable_key_rotation`, `storage_encrypted`,
`publicly_accessible`) to a literal, so they are known at plan time. Turning
them on should not block an existing workspace. Run `enable_policy_sets` in a non-production project first
and read the advisory results before relying on them.

## The TFC-layer guard in practice

`tfc_admin_guard` stops some changes that are routine, so the security team
overrides them on the run after reading the plan:

- **A new environment** creates workspace-level team grants (a non-production
  workload in a shared project gets `tfe_team_access` write) and, on its first
  production environment, an approvers project grant. Once its credential
  inputs are set, it also creates the `TFC_*` dynamic-credential env vars.
- **Wiring dynamic credentials** (tfc-admin pass 2) creates or changes the
  `TFC_*` env vars of every workspace it wires, and any later change to a
  plan or apply role or service account does the same.
- **A `TF_CLI_ARGS_plan` env var** set through `workspace_variables`
  ([add-environment.md](../runbooks/add-environment.md), step 7).
- **A move between projects** of a control-plane or production workspace, for
  example when `split_workload_projects` changes.
- **Removing an environment** drops its workspace from both sets'
  `workspace_ids`.
- **The sandbox estate** (`auto_apply_on_merge = true`) creates control-plane
  workspaces with `auto_apply` on.

Limits: when the same plan creates a workspace, the new ID is unknown and
`workspace_ids` cannot be compared, so a removal hidden behind an addition in
one plan is not caught by that rule (the deletion and repointing rules still
apply). The rule judges `tfe_*` resources in any workspace, but only tfc-admin
declares them. Organization owners keep their implicit access, and a policy
override is itself an org-wide permission, so separation of duties still rests
on CODEOWNERS. `policies/**` lists the security team alone, so a policy change
needs a security approval. `envs/tfc-admin/**` lists the platform and the
security team, so a platform approval alone satisfies it
([branch protection](../guides/BRANCH_PROTECTION.md#what-code-owner-review-enforces)).

## Adding a policy

1. Create `policies/opa/<name>.rego` with `package terraform.policies.<name>`,
   `import rego.v1` and `import data.terraform.lib`. Emit messages from a
   `deny contains msg if { ... }` rule, or from `warn` for an advisory companion
   query in the same package.
2. Filter with `lib.written_of_type("<type>")` (create/update/replace, managed
   only). In a mandatory rule, use `lib.unknown_or_not(rc, attr, want)`, so that
   an unknown value fails, and append `lib.unknown_hint` to the message. Use
   `lib.known_and_not(rc, attr, want)` (unknown values pass) only in an advisory
   rule, or when the attribute is genuinely computed at apply time.
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
