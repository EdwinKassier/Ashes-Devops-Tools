# Upgrading

How a fork takes a new release of this landing zone, and what to check when it
does. The newest release is first. Every release has one section of manual
steps and one sandbox upgrade log.

## What you own and what upstream owns

A fork keeps upstream's code and adds its own configuration on top. Merges stay
clean when you edit only the files below, which upstream never changes:

| Fork-owned path | Holds |
|---|---|
| `config/*.yaml` (including `config/sandbox/`) | Your landing-zone configuration, TFC workspace overrides and sandbox config. Upstream ships only `*.example.yaml` and fixtures. |
| `.github/CODEOWNERS` | Your review teams. The scaffolder writes it. |
| `envs/**/backend_override.tf` | Your state backend choice for each root (self-managed state). |
| `envs/gcp/guardrails/guardrails.auto.tfvars` | Your GCP IAM deny policies, owned by the security team. |

Everything else (modules, stages, roots, policies, workflows, docs) is
upstream's. If you need to change one of those, send it upstream or carry the
patch knowingly and expect conflicts here.

## Merging a release tag

1. Read the section for each release between your current tag and the new one,
   oldest first. Run every manual step marked as needed before the apply.
2. `git fetch upstream --tags && git merge <tag>`. Conflicts mean a file outside
   the table above was edited in your fork.
3. Regenerate anything your fork pins: `make docs`, and the lockfiles for any
   root you touched (`terraform providers lock -platform=linux_amd64
   -platform=darwin_arm64 -platform=darwin_amd64`).
4. Apply the new tag to your **sandbox** first. The sandbox runs the previous
   release, so the apply is a real N-1 to N upgrade. Fill in the release's
   sandbox upgrade log (template below).
5. Promote layer by layer in apply order. Plans that delete or replace a
   stateful resource stop on `destroy_guard` until the security team overrides
   the run; record every override with its reason in the log.

## Unreleased

Manual steps for the next release, grouped by area. A breaking change
(`feat!:` or a `BREAKING CHANGE` footer) must add its entry here; CI enforces it.

### HCP Terraform and policy

#### Run triggers auto-apply explicitly non-prod workloads (tfc-admin)

**Trust change on the upgrade apply.** tfc-admin's new
`enable_nonprod_workload_auto_apply` defaults to `true`. Every
`gcp-workload-<env>` / `aws-workload-<env>` whose environment sets
`is_production: false` **explicitly** gets `auto_apply_run_trigger` and
`queue_all_runs`. A confirmed upstream apply (`gcp-network-hub`, `aws-network`,
`aws-security`) then applies those workloads with no second confirmation.
An omitted `is_production` keeps manual confirmation. Production workloads and
every shared workspace are unchanged.

**To keep the previous behaviour,** set `enable_nonprod_workload_auto_apply = false`
on tfc-admin **before** the upgrade apply.

Also in this release (no manual step):

- tfc-admin now triggers `aws-organization` after each of its applies. It
  triggers `gcp-bootstrap` too once that runs remotely
  (`workspace_execution_modes = {}`). Plans with no changes end as "planned and
  finished".
- With `gcp_bootstrap_outputs_from_tfc`, tfc-admin derives each
  `gcp-workload-<env>`'s SA emails from `org.prefix` (or `gcp_project_prefix`)
  and the gcp-bootstrap `admin_project_id` output. A `check` warns when a
  derived email disagrees with a gcp-bootstrap output; align `org.prefix` with
  gcp-bootstrap's `project_prefix`. The plan fails on an invalid prefix or on
  `<prefix>-wl-<env>-apply` over 30 characters.
- A `check` warns while `gcp_bootstrap_outputs_from_tfc` is on and
  `gcp-bootstrap` still runs locally.

#### The destroy guard is mandatory, in its own overridable policy set

`destroy_guard` moves from `policies/opa/` (advisory) to
`policies/opa-destructive/` (mandatory), and tfc-admin attaches it as a second
set, `<project_name_prefix>destructive-change-guard`, with `overridable = true`.
It now denies every delete or replace of a stateful type (databases, buckets,
KMS keys, projects/folders/accounts, networks, secrets, log sinks/buckets,
CloudTrail, StackSet instances, `supabase_project`), not only log-named
buckets. The `<prefix>opa-guardrails` set stays non-overridable.

**Manual steps (estates with policy sets on):**

1. An organization owner creates a `security` team in HCP Terraform (if it does
   not exist), grants it **Manage Policy Overrides** in the organization
   settings, and sets its ID as tfc-admin `security_team_id`. Without it only
   owners can override an intended destroy (a check warns).
2. Set `org.tfc.plan` in `config/landing-zone.yaml` (`free | essentials |
   standard | premium`). `enable_policy_sets` now defaults to null: on with
   `vcs_repo` and a `standard` or `premium` plan. An explicit
   `enable_policy_sets` still wins. Without `org.tfc.plan` the sets stay off,
   as before, and a `destructive_changes_guarded` check warns.
3. Expect plans that delete or replace a stateful resource to stop on
   `destroy_guard` until the security team overrides the run.

`drift-detection.yml` now fails a leg whose workspace does not exist instead of
skipping it. A single-cloud estate sets the `TFC_DRIFT_WORKSPACES` repository
variable to its own workspaces (or `REAL_CLOUD_CHECKS_OPT_OUT=true`).

### AWS

#### AWS Config recorders move to an aws-organization StackSet

The workload roots no longer manage a Config recorder. `aws-organization`
deploys recorders org-wide: a service-managed StackSet, `org-config-recorders`,
covers every member account except security tooling, and the management account
gets a direct recorder. A new recorder SCP then limits who can change them.
Everything is behind flags that default to `false`, so nothing changes until
you follow the runbook.

**What changes on the next plan (no manual step):**

- **aws-workload-<env>**: `module.config_recorder` leaves state through a
  `removed` block with `destroy = false`. The live recorder, delivery channel
  and service-linked role stay in the account and keep recording. The plan must
  show no destroy.
- `config_role_arn` and `create_config_service_linked_role` (workload stage and
  root) are deprecated and ignored. A check warns while they are set. The
  workload `config_role_arn` output is now always null. All three are removed
  in v1.0.
- **securityhub-org** rejects `EC2.6` in `disabled_control_identifiers`.

**Manual steps (existing AWS estates):** follow
[`docs/runbooks/aws-config-recorder-migration.md`](docs/runbooks/aws-config-recorder-migration.md).

1. Upgrade the workload roots.
2. Apply aws-security.
3. Apply aws-organization with `enable_org_config_recorders = true` and
   `org_config_recorders_failure_tolerance_percentage = 100`.
4. Delete the legacy recorders with `scripts/aws-delete-legacy-recorders.sh`
   (break-glass, dry-run first).
5. Re-apply aws-organization with tolerance `0`.
6. Apply aws-organization with `enable_config_recorder_scp = true`.

A greenfield estate sets both flags to `true` once aws-security has applied
(`scripts/init-landing-zone.sh --aws-config-recorders true`). Until you
complete the migration, the accounts outside the workload roots (Infrastructure,
log archive, forensics, management) have no recorder, as before.

**Legacy removal in v1.0:** the workload `removed` block, the deprecated
workload inputs and output, and the flag-off path of the recorder SCP (the
recorder actions in `DenyWeakenSecurityServices`).

#### AWS management KMS access by key policy, not tags

`tfc-management-roles` no longer grants the aws-security apply role `kms:*` on
keys carrying `Workspace = aws-security` (a tag anyone with `kms:TagResource`
could plant). `CreateOwnedKeysOnly` stays unchanged (owner request tag required). The org trail's CloudWatch Logs CMK is instead managed through
its own key policy: a new `PipelineKeyManagement` statement
(`cloudwatch_logs_kms_key_manager_arns`, defaulting to the
`tfc-mgmt-aws-security-apply` role) grants describe/get/list, rotation,
description, tags and aliases, plus data-key use (`PipelineKeyUseViaServices`,
`kms:ViaService` SNS and Logs only). The account-root `kms:*` statement is kept.

**Manual step for existing estates (before applying the new
`tfc-management-roles`):** the pipeline's `kms:PutKeyPolicy` is denied, so the
new statement must be added once, by a break-glass principal (the account root
or an administrator in the management account). Without it, the next
aws-security plan/apply gets AccessDenied on the key. Substitute your values:

```sh
KEY_ID=$(aws kms describe-key --key-id alias/<trail_name>-cloudwatch --query KeyMetadata.KeyId --output text)
aws kms get-key-policy --key-id "$KEY_ID" --policy-name default --query Policy --output text > policy.json
# Edit policy.json: append these statements to "Statement" (keep the existing ones):
#   {"Sid":"PipelineKeyManagement","Effect":"Allow",
#    "Principal":{"AWS":"arn:aws:iam::<MGMT_ACCOUNT_ID>:role/tfc-mgmt-aws-security-apply"},
#    "Action":["kms:Describe*","kms:Get*","kms:List*","kms:EnableKeyRotation",
#              "kms:UpdateKeyDescription","kms:TagResource","kms:UntagResource",
#              "kms:CreateAlias","kms:UpdateAlias","kms:DeleteAlias"],
#    "Resource":"*"}
#   {"Sid":"PipelineKeyUseViaServices","Effect":"Allow",
#    "Principal":{"AWS":"arn:aws:iam::<MGMT_ACCOUNT_ID>:role/tfc-mgmt-aws-security-apply"},
#    "Action":["kms:GenerateDataKey*","kms:Decrypt"],"Resource":"*",
#    "Condition":{"StringEquals":{"kms:ViaService":
#      ["sns.<REGION>.amazonaws.com","logs.<REGION>.amazonaws.com"]}}}
aws kms put-key-policy --key-id "$KEY_ID" --policy-name default --policy file://policy.json
```

Then upgrade `tfc-management-roles`, and confirm aws-security plans with no
changes to the key policy. Fresh estates need nothing.

#### aws-security cannot disable org detection; org-owned guard alerts

`tfc-management-roles` drops these actions from the aws-security apply role:
`Disable*AdminAccount`, `fms:DisassociateAdminAccount`,
`organizations:DisableAWSServiceAccess`,
`DeregisterDelegatedAdministrator` and `cloudwatch:DeleteAlarms`. It now
denies trail untagging and resource-policy edits, CIS-alarm deletion and
disabling, and trail log-group, log-stream, metric-filter and retention deletion.
`aws-organization` creates `org-guard-alerts` in us-east-1 of the management
account: a CMK, an SNS topic and an EventBridge rule. It also creates one
forwarding rule per other `aws.enabled_regions` region, plus the
`org-guard-alerts-forwarder` IAM role.

- **No manual step for a routine upgrade.** Apply `aws-organization` first; it
  only adds resources. Optionally set `aws.guard_alert_emails`, then confirm
  each subscription email.
- **A plan that now replaces a CIS alarm or metric filter fails** with
  AccessDenied on the delete. Run that apply as break-glass or the phase-0
  role.
- **Removing a tag key from the org trail needs break-glass.**
  `cloudtrail:RemoveTags` is denied, so a plan that drops a tag from the trail
  (for example, a removed `default_tags` key) fails with AccessDenied. Changing
  a tag's value still works.
- **Destroying aws-security** (or removing a delegated admin) needs
  `enable_security_service_teardown = true` on `aws-organization`. See
  `docs/runbooks/aws-teardown.md`.

#### Production egress fails closed (aws-network)

`aws-network` now fails the plan when the profile is `production` and an AWS
workload environment `is_production` (unset = keys `prod` / `production`) unless
unmatched egress is dropped and a domain allowlist is set. Before upgrading,
set in `config/landing-zone.yaml` (seed in `config/landing-zone.example.yaml`):

```yaml
aws:
  network:
    egress_domain_allowlist: [.amazonaws.com, .github.com, .githubusercontent.com, .terraform.io]
    stateful_default_actions: [aws:drop_established, aws:alert_established]
```

Extend the allowlist with every domain your workloads reach first: all other
HTTP/TLS egress is dropped once applied. To keep alert-only inspection while
you build the list, set `aws.network.egress_alert_only_waived: true` (an
explicit, reviewable waiver). Starter-profile estates are unaffected.

### GCP

#### GCP deny policies move to the security-team `gcp-guardrails` workspace

In the default `guardrail_owner_mode = "separate"` the org IAM deny policies
(admin containment `contain-admin-identity` plus `iam_deny_policies`) are now
authored and applied by a new root, `envs/gcp/guardrails` (workspace
`gcp-guardrails`, stage `modules/gcp/stages/guardrails`). This replaces the
manual `gcloud iam policies create|update` step. The workspace sits in its own
HCP project where only the security team has access, and it runs as the
gcp-bootstrap guardrails SAs, WIF-bound by workspace ID only.

**What changes on the next plan (no manual step):**

- **gcp-organization (separate mode)** no longer builds the deny policies. Its
  `admin_containment_rules` and `guardrail_deny_policy_specs` outputs are empty,
  and a check warns if `iam_deny_policies` is still set there.
  `guardrail_deny_policy_specs` is deprecated and is removed in v1.0. The
  containment tag and its bindings are unchanged.
- **gcp-organization (legacy organization mode)** keeps applying the policies
  under the same state addresses. One fix is applied: the audit-store rule's
  condition now passes the namespaced IDs
  (`resource.matchTagId('tagKeys/<n>', 'tagValues/<n>')`) where it used to pass
  the bare numeric names. `contain-admin-identity` updates in place.
- **gcp-bootstrap** adds a `<prefix>-guardrails-plan` SA (`iam.denyReviewer`,
  `resourcemanager.tagViewer`, `organizationViewer`), gives the guardrails apply
  SA `resourcemanager.tagViewer`, and binds both to `gcp-guardrails` (variable
  `guardrails_workspace`) by its `tfc_workspace_ids` entry. There is never a
  binding by name. **A production estate fails the gcp-bootstrap plan** until
  `tfc_workspace_ids` holds the `gcp-guardrails` ID. tfc-admin writes it when
  `set_gcp_bootstrap_workspace_ids` is on (the default); for the local phase-0
  apply use its `gcp_bootstrap_tfvars` output. `guardrails_workspace = null`
  opts out and keeps only the PAM break-glass path.
- **tfc-admin** adds the `gcp-guardrails` workspace and the
  `<project_name_prefix>guardrails` project (config key
  `org.tfc.guardrails_project` overrides the name). It also adds the
  `security_team_id` variable (default null; the security team gets write on
  that project, and no other team gets any access). With it null, a check warns
  and only organization owners can run the workspace.
  `speculative_enabled = false`, `auto_apply = false`, no UI destroy plans.

**Manual steps for an existing separate-mode deployment** (the policies were
applied by hand from `guardrail_deny_policy_specs`):

1. Create a `security` team in HCP Terraform (owners) and set
   `security_team_id`. Apply `tfc-admin`.
2. Apply `gcp-bootstrap` (it picks up the `gcp-guardrails` ID).
3. Move any `iam_deny_policies` from the gcp-organization variables to a
   committed `envs/gcp/guardrails/guardrails.auto.tfvars` (CODEOWNERS: platform +
   security; `.gitignore` exempts it). Do not set them as `gcp-guardrails`
   workspace variables: the security team's grant is variables read-only, and
   the workspace gets no shared variable set.
   - If gcp-organization runs with `enable_principal_access_boundary = true`,
     set `gcp.principal_access_boundary: true` in `config/landing-zone.yaml`
     instead (gcp-bootstrap, gcp-organization and gcp-guardrails all read it;
     variable > config > false). Otherwise gcp-guardrails plans the containment
     policy WITHOUT the boundary update/delete/unbind rules and drops them on
     its first apply. Then remove the per-root variable.
   - If gcp-bootstrap sets `tfc_project_ids` (the WIF provider's TFC project
     allow-list), add the new guardrails HCP project's `prj-...` ID (tfc-admin
     output `project_ids["guardrails"]`) and re-apply gcp-bootstrap, or the
     gcp-guardrails token is rejected by the provider condition.
4. In `gcp-guardrails`, adopt each existing policy instead of creating it. The
   create would fail with 409. Run the import as the security team with an
   `import` block in a reviewed PR, or once from the workspace:
   `terraform import 'module.guardrails.module.iam_deny.google_iam_deny_policy.this["contain-admin-identity"]' 'cloudresourcemanager.googleapis.com%2Forganizations%2F<ORG_ID>/contain-admin-identity'`.
5. Queue a run on `gcp-guardrails`; the security team confirms it. Expect an
   in-place update of the tag condition (namespaced IDs, see above).

**Tag IDs are namespaced (all estates).** `google_tags_tag_key` /
`google_tags_tag_value` `.name` is the bare numeric ID, but tag-value
parents, tag bindings and `matchTagId` take `tagKeys/<n>` / `tagValues/<n>`.
`modules/gcp/governance/tags` now outputs the namespaced form (and builds the
tag-value parent from it). Consumers that took the bare form were wrong:
gcp-projects' `tag_bindings` validation (`^tagValues/[0-9]+$`) rejected it,
and the containment bindings and deny condition passed bare numbers. Expect on
the next gcp-organization plan:
- `google_tags_tag_value.values`: no change. `parent` is ignored after create
  because it is immutable and fixed by the key.
- `google_tags_tag_binding.environment` and
  `google_tags_location_tag_binding.containment_*`: if your state holds a bare
  `tag_value`, they are **replaced** (`tag_value` is immutable). Each binding is
  briefly absent; with containment on, apply outside change windows that touch
  the audit store.
- `contain-admin-identity` (organization mode): the condition updates in place.
- The `tag_keys` / `tag_values` outputs of gcp-organization change form. A
  `gcp.contracts.organization.tag_values` override in config must use
  `tagValues/<n>`, as the validation already required.

**Migrating from `guardrail_owner_mode = "organization"` to `"separate"`:**
switch gcp-bootstrap first. Then run
`terraform state rm 'module.organization.module.iam_deny.google_iam_deny_policy.this'`
in gcp-organization before its next apply (its apply SA can no longer delete
the policies, which is the point). Then follow steps 1-5. Do not run
`gcp-guardrails` while either root is still in organization mode: both would
manage the same policies.

**v1.0 legacy removal:** `guardrail_owner_mode = "organization"` (the in-stage
apply, and `roles/iam.denyAdmin` on the organization apply SA) and the
`guardrail_deny_policy_specs` output are removed in v1.0.

#### GitHub workload identity: exact-match owner pin, ref/env pins in bindings

Every GitHub Actions workload identity provider this repo creates now has the
attribute condition `assertion.repository_owner_id == "<id>"` and nothing else.
`custom.wifProviderTenantPinned` accepts only that exact string. Repository, ref
and environment pins moved into the principalSet each service account is bound
to.

**`modules/gcp/iam/workload-identity` (breaking inputs):**

- `github_attribute_condition_override` is removed. A custom condition could
  never satisfy the exact-match tenant pin. Pin repositories, refs and
  environments through `github_sa_bindings` and `github_allowed_refs` instead.
- `github_organization` is removed. The condition pins the immutable
  `github_repository_owner_id`, never the renameable owner name.
- `github_repository_owner_id` is required when `enable_github_provider = true`.
- `github_allowed_refs` entries must be exact refs (`^[A-Za-z0-9_./-]+$`): a
  principalSet value cannot hold a wildcard. When it is set, each
  `github_sa_bindings` entry needs `repository_id`, and is bound once per ref on
  `attribute.repo_ref/<repository_id>/<ref>`. With one ref the binding keeps its
  for_each key; with several, each key becomes `<key>:<ref>`.
- **Behaviour change:** with `github_allowed_refs` empty the old computed
  condition still limited `assertion.sub` to `refs/heads/main`. The bindings now
  stay on `attribute.repository_id`, so any ref of the bound repository can
  impersonate. Set `github_allowed_refs = ["refs/heads/main"]` to keep the old
  restriction.

**`modules/gcp/stages/app-services` / `gcp-workload-<env>`:**

- `github_repository_owner_id` is required once a service declares `github`
  (`gh api orgs/<org> --jq .id`). It was optional.
- `services[*].github.ref` and `.environment` must match `^[A-Za-z0-9_./-]+$`,
  and `environment` may not be `-` (the value a token without an environment
  claim maps to).

**What the next apply does (no manual step):**

- The GitHub providers (app-services `github`, gcp-bootstrap `gh_oidc`) update
  in place: the condition is normalised to the canonical double-quoted form and
  three mapped attributes are added.
- Each GitHub `roles/iam.workloadIdentityUser` binding whose pin changes is
  replaced (`member` is immutable). For the few seconds between the delete and
  the create, that deploy SA cannot be impersonated; do not run a deploy during
  the apply.

**Before you apply `gcp-organization` with `wif_github_owner_ids` set:** apply the
workload and bootstrap roots first. A provider that still carries the old
condition is denied on its next UPDATE (not on its existing state) until it is
rewritten.

### SaaS and cross-cloud

#### SaaS secret bridge writes its secret write-only

Applies to workloads with `enable_saas_secret_bridge = true`.

- **AWS (`aws-workload-<env>`).** `aws_secretsmanager_secret_version.saas_bridge`
  moves from `secret_string` to the write-only `secret_string_wo`. The plan shows
  an **in-place update**, not a replacement: aws 6.45 and later switch in place,
  and the repo floor is 6.46. Afterwards the secret version holds no plaintext
  in state. The secret's content does not change.
- **GCP (`gcp-workload-<env>`).** The secret was already write-only. Its
  version counter now comes from the saas `bridge_version` output. It stays 1
  until you bump `saas.bridge_rotation`, so the upgrade re-writes nothing.
- **Rotation.** A write-only value is not diffed. After rotating a bridged
  Supabase secret, bump `saas.bridge_rotation`, apply `saas-<name>`, then apply
  each bridging workload
  ([saas-bootstrap](docs/runbooks/saas-bootstrap.md#bridging-secrets-to-a-workload-and-rotating-them)).
  A `saas-<name>` that has not applied the new output yet counts as version 1.
- **Still in workload state.** The values pass through
  `data.terraform_remote_state.saas`, whose result is stored in the workload's
  state. Task 3.6 moves this read to `ephemeral "tfe_outputs"` (see
  `docs/known-gaps.md`).

### All clouds

#### Removed: `modules/gcp/stages/host` and `modules/gcp/network/dns-records`

Both modules had no caller in this repo. `stages/host` (the deprecated network
facade) is replaced by `stages/net-hub`, `stages/dns-anchor` and
`stages/net-spoke`; `network/dns-records` duplicated `network/dns`.

No manual step for the landing-zone roots. A fork that calls either module from
its own root must move off it before taking this release: use the replacement
stages above, or declare the records through `modules/gcp/network/dns`.

#### One `contract` output per producer root

Every producer root (`aws-organization`, `aws-security`, `aws-network`,
`gcp-bootstrap`, `gcp-organization`, `gcp-projects`, `gcp-network-hub`) now
publishes one non-sensitive `contract` output: an object holding every key it
already exported. The roots in this repo, and tfc-admin's `tfe_outputs` reads,
now read only `.outputs.contract` (`.nonsensitive_values.contract`).
`scripts/check-contracts.sh` (`make consistency`, CI) enforces it.

No manual step. Upgrade apply order is unchanged.

- **Before a producer re-applies,** its state has no `contract` output yet.
  Consumers then fall back to the old individual outputs, which hold the same
  keys, so a consumer that plans first still plans with no changes.
- **The individual outputs stay** as deprecated aliases. Their descriptions say
  `Deprecated: read contract.<key>`. A consumer outside this repo should switch
  to `outputs.contract.<key>` before v1.0.
- **The `<layer>_contract` override variables share one type per upstream.**
  For example, `organization_contract` has the same type in every aws root.
  Fields that only some roots need are now `optional`. A root that needs a field
  checks it in a variable validation, and the error names the field. Existing
  overrides and `<cloud>.contracts.*` config keep working unchanged.
- **New guard resources.** aws-backup, gcp-projects, gcp-network-hub and
  gcp-workload each plan one new `terraform_data` contract guard (a create,
  with no cloud resource). It fails the plan with the missing contract field
  named, for example `ou_ids["Workloads"]` or `environment_config["<env>"]`,
  whatever the source: variable, config or remote state.
- **The gcp-organization admin-containment preconditions** moved from the
  `admin_containment_enabled` output to the `contract` output.

## Sandbox upgrade log

Copy this block once per release, fill it in from the sandbox run, and commit it
with the merge. An empty log means the release was not proven in the sandbox.

```markdown
### Sandbox upgrade log: <tag>

- Previous release (N-1): <tag>
- Sandbox applied on: <date>, by <name>

| Workspace | N-1 to N apply result | Plan summary (add/change/destroy) | Notes |
|---|---|---|---|
| <workspace> | <success / failed / skipped> | <+a ~c -d> | <link to run> |

`destroy_guard` overrides:

| Workspace | Resource | Reason | Approved by |
|---|---|---|---|
| <workspace> | <address> | <why the delete or replace is intended> | <security team member> |
```

## Legacy modes removed at v1.0

Each dual mode keeps both paths until v1.0. Migrate before then.

| Legacy mode | Replacement | Entry |
|---|---|---|
| `guardrail_deny_policy_specs` output on gcp-organization | Policies authored in `envs/gcp/guardrails` | GCP deny policies move to the security-team `gcp-guardrails` workspace |
| `guardrail_owner_mode = "organization"` (in-stage apply, `roles/iam.denyAdmin` on the organization apply SA) | `guardrail_owner_mode = "separate"` | GCP deny policies move to the security-team `gcp-guardrails` workspace |
| Workload `removed` block for `module.config_recorder`, the deprecated `config_role_arn` and `create_config_service_linked_role` inputs, and the `config_role_arn` output | The `org-config-recorders` StackSet in aws-organization | AWS Config recorders move to an aws-organization StackSet |
| Flag-off recorder path of the SCP (recorder actions in `DenyWeakenSecurityServices`) | `enable_config_recorder_scp = true` | AWS Config recorders move to an aws-organization StackSet |
| The individual cross-root outputs of the producer roots, and the consumers' fallback to them when `contract` is absent | The `contract` output (`outputs.contract.<key>`) | One `contract` output per producer root |
