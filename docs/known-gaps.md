# Known Gaps & Preview Features

A single, honest inventory of things that are **not yet done, not yet validated,
or deliberately deferred**. This exists so `CLAUDE.md` can stay a doc of
always-true authoring rules instead of a running bug list, and so a new
maintainer has one place to see what's aspirational vs load-bearing.

Status legend: **OPEN** (a real gap to fix) · **PREVIEW** (code shipped, opt-in,
default-off, not yet validated against a real apply) · **BLOCKED** (waiting on an
upstream/provider capability) · **DECISION** (needs a human call before action).

## OPEN — validate before relying on

- **Upstream applies auto-apply non-prod workloads.** Workload
  `gcp-workload-<env>` / `aws-workload-<env>` workspaces whose environment sets
  `is_production: false` explicitly (an omitted flag never qualifies) get
  `auto_apply_run_trigger` and `queue_all_runs`
  (`enable_nonprod_workload_auto_apply`, default true). The trust change: a
  human confirms the upstream apply (`gcp-network-hub`, `aws-network`,
  `aws-security`), and the run it queues on each non-prod workload then applies
  **without a second confirmation**. So whoever may confirm a shared
  network/security apply can change non-prod workloads too. Production
  workloads, the control plane, `gcp-guardrails` and `tfc-admin` still confirm.
  Residuals, not yet run in the sandbox:
  - the run `queue_all_runs` starts when tfc-admin creates the workspace is
    **expected to fail**: it runs before `gcp-bootstrap` creates its SAs (or
    `aws-organization` trusts its name). The setting exists so later VCS and
    run-trigger runs queue without a manual first run; the workload builds from
    the run trigger of the next upstream apply. If that apply is a no-op (no
    trigger fires), queue the workload's run once by hand;
  - the `tfc-admin -> gcp-bootstrap` / `aws-organization` triggers queue a plan
    on both roots after **every** tfc-admin apply. A plan with no changes ends
    as "planned and finished" and needs no action. `gcp-bootstrap` is a target
    only once it runs remotely (`workspace_execution_modes = {}`);
  - **a new AWS workload still needs a second tfc-admin pass.** Its
    `TFC_AWS_*` role ARNs come from the `aws-organization` outputs
    (`tfc_plan_role_arns` / `tfc_apply_role_arns`, keyed by account key), and a
    new workload account's roles exist only after `aws-organization` applies.
    Re-apply tfc-admin then. Only GCP workload SA emails are derived;
  - with `auto_apply_on_merge` (sandbox only) a tfc-admin apply auto-applies
    `gcp-bootstrap` and `aws-organization`.

- **Org-wide Config recorders are mock-tested only.** The
  `org-config-recorders` StackSet (`modules/aws/security/config-recorder-stackset`)
  and the migration runbook
  ([`aws-config-recorder-migration.md`](runbooks/aws-config-recorder-migration.md))
  have not run in the sandbox. **Validate:**
  - a fresh account's first `PutConfigurationRecorder` with the
    `AWSServiceRoleForConfig` ARN creates the service-linked role, since the
    template creates no IAM resources;
  - the CloudFormation-created recorder starts recording without an explicit
    `StartConfigurationRecorder`;
  - the `DIFFERENCE` filter keeps security tooling out on auto-deployment too;
  - SUSPENDED or closed accounts under the root (Suspended OU, accounts
    pending closure) do not fail or block the StackSet operations, and the
    tolerance-0 re-run still succeeds with them present;
  - StackSets can re-run an instance whose earlier stack is `ROLLBACK_COMPLETE`
    (runbook step 5);
  - `SOFT_FAILURE_TOLERANCE` with tolerance 100 lets the migration pass apply;
  - the recording gap between runbook steps 4 and 5. Record it in the runbook.

- **Flow-log and log-archive bucket-policy changes by the owning pipeline are
  detected, not prevented.** The deny-tamper SCP still exempts the pipeline
  roles from `ec2:DeleteFlowLogs`, because flow-log replacement is routine, and
  from the log-archive `s3:PutBucketPolicy` / `DeleteBucketPolicy`, because
  aws-security owns that policy. A compromised owning pipeline can remove a flow
  log or rewrite the bucket policy. The change is caught by Security Hub
  `EC2.6`, which can no longer be disabled (`securityhub-org` validation), and
  by the CIS 4.8 (bucket policy) alarm in `cloudtrail-org`. It is not blocked.

- **The StackSet administrator can deploy to every account.** `aws-organization`
  owns the service-managed StackSets (recorders, TFC OIDC baseline, member
  break-glass, Backup role), and its `stacksets-exec-*` execution role is exempt
  from the recorder SCP and the StackSet role-tamper deny. Whoever can apply
  `aws-organization` can therefore run any template in any member account.
  This is inherent to StackSets. The control is who can apply
  `aws-organization` (phase-0 role, policy sets, workspace access), not an SCP.

- **Essentials-plan support for VCS policy sets is unverified.** tfc-admin
  turns the policy sets on by default only for `org.tfc.plan` `standard` or
  `premium` (`envs/tfc-admin/config.tf`, `local.enable_policy_sets`). Whether
  HCP Terraform Essentials allows VCS-sourced OPA policy sets, and how many
  policies it allows per set, has not been checked against the current HCP
  pricing and limits. **Validate:** on an Essentials organization, create both
  sets; if they work, add `essentials` to the default list. Until then an
  Essentials estate sets `enable_policy_sets = true` itself, or runs without
  the destroy guard (the `destructive_changes_guarded` check warns).

- **Region SCP no longer exempts the run role.** `scp-region-restriction`
  now exempts break-glass only; global-endpoint services stay in `NotAction`
  (plus `networkmanager:*` and `notifications:*`). Mock-tested only.
  **Validate in the sandbox:** a routine plan and apply of every member-account
  layer, run as `tfc-plan`/`tfc-apply`, makes no call that this SCP denies. A
  global-endpoint API missing from `NotAction` would surface here.

- **TFC organization owners are the root of AWS trust.** AWS OIDC trust can
  condition only on the claims `aud`, `sub`, `amr`, `email` and `oaud`, so
  trust is bound by **workspace name**. Anyone who can create or rename a
  workspace in the TFC organization can mint a token that matches a trust
  policy. Keep at least 2 organization owners, never use them day to day, and
  let only owners rename or create workspaces. The `platform` team's custom
  access already forbids both. `aws-network` is now in
  `speculative_disabled_workspaces` with the other control-plane roots, so a
  PR's code never runs with its plan identity. Not enforceable in code:
  membership of the owners team is an operator control
  ([`BRANCH_PROTECTION.md`](guides/BRANCH_PROTECTION.md#tfc-organization-owners)).

- **tfc-admin team-token permissions are unvalidated.** tfc-admin runs on a
  non-owner `tfc-admin` team token (`manage_workspaces`, `manage_projects`,
  `manage_policies`, `manage_vcs_settings`; runbook
  [`tfc-admin-token-rotation.md`](runbooks/tfc-admin-token-rotation.md)). No
  real HCP access exists to prove that set covers every resource tfc-admin
  manages, notably organization-level variable sets and policy sets. If the
  first plan shows a permission error that only owners can clear, that resource
  is a residual owner-only step: document it in the runbook rather than
  widening the team to `manage_teams` or `manage_organization_access`. The
  90-day token expiry and rotation are an operator control, not enforced in code.

- **Org-trail selector changes are detected, not prevented.** The
  aws-security management apply role keeps `cloudtrail:PutEventSelectors` /
  `PutInsightSelectors`, because `aws_cloudtrail` calls them on create. A
  selector change (for example, dropping management events) is caught only
  by the `org-guard-alerts` EventBridge rule. That rule is in us-east-1 plus
  forwarders in every other enabled region, and it is owned by
  `aws-organization`. The CIS 4.5 alarm does not match selector calls. This
  stays detect-only until Task 1.11 moves trail management to security
  tooling, where the SCP applies. The rules and forwarding are mock-tested
  only. **Validate in the sandbox:** a `PutEventSelectors` call and a
  GuardDuty admin call made from a non-us-east-1 region must both email the
  topic.

- **CIS-alarm silencing is detected, not prevented.** The aws-security role
  needs `cloudwatch:PutMetricAlarm`, `logs:PutMetricFilter` and `sns:*` on
  `<trail>-*` topics for routine applies. A call through one of them can
  silence the CIS alerting:
  - an alarm rewritten with `ActionsEnabled=false` or no alarm actions;
  - a CIS metric filter overwritten;
  - the `<trail>-cis-alarms` topic deleted, re-attributed or unsubscribed.

  Each of these is matched by the `org-guard-alerts` rule, but none is
  denied. Deleting or disabling alarms, and deleting log streams, metric
  filters or the log group, are denied. Matching "no alarm actions" uses
  `alarmActions: [{exists: false}]`, which may miss an explicitly empty list.
  **Validate in the sandbox.**

- **A1 — CloudTrail KMS grant condition.** `modules/aws/security/cloudtrail-org`
  scopes the log-service KMS grant with `aws:SourceOrgID`, but AWS documents
  `aws:SourceArn` (the trail ARN) as the CloudTrail KMS-key-policy condition
  (`aws:SourceOrgID` is documented for the S3 *bucket* policy). If CloudTrail does
  not emit `SourceOrgID` on its KMS calls, log delivery fails. Only mock-tested.
  **Validate on a real org and switch CloudTrail to `aws:SourceArn` before
  relying on it.** Ref: <https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-kms-key-policy-for-cloudtrail.html>

- **G13 — stage contract overrides are hand-maintained and mock-tested only.**
  Every root's `<layer>_contract` (or `<cloud>.contracts.<layer>` in
  `config/landing-zone.yaml`) replaces the upstream `terraform_remote_state`
  read; a supplied contract does **not** follow an upstream rename/rotation
  (e.g. the log archive bucket, audit M7) — keep it in sync or prefer the
  read. Standalone `aws-workload` (`enable_network_hub = false`) has no egress
  and still plans the (unused) `tgw` subnet tier; attaching later replaces the
  VPC if it then moves to an IPAM pool. `gcp-workload`'s `module "host"` must
  consume `local.hub_vpc_peerings` / `local.hub_dns_zones` / `local.org_id`.
  **Validate** a contract-only plan against a real estate before relying on it.

- **C2 — per-stage GCP automation identities (supersedes G3).** Shipped
  default-ON in `modules/gcp/stages/bootstrap` (`service_accounts.tf`): a
  read-only plan SA and a least-privilege apply SA per control-plane stage and
  per `gcp-workload-<env>`, WIF-bound per (workspace, run phase) via composite
  `attribute.workspace_phase` / `workspace_id_phase`; workload SAs hold no
  org-level role (env-folder grants in `modules/gcp/stages/projects`); GitHub
  WIF off by default and ID-pinned. The old opt-in `enable_privilege_split` /
  resman SA is **removed**. Mock-tested only — **validate on a real org**:
  (1) the composite `<name>:<phase>` principalSet values authenticate as
  expected; (2) the role matrix is sufficient for each stage's first apply
  (notably `logging.configWriter` vs `logging.admin`,
  `securitycenter.notificationConfigEditor`, `monitoring.metricsScopesAdmin`,
  that the metadata-only plan role set (predefined viewers + the
  `landingZonePlanViewer` custom role) is enough for every stage's plan, and that
  bootstrap-apply's org `iam.securityAdmin` covers billing-account IAM);
  (3) the projects-apply `modifiedGrantsByRole` delegated-grant condition is
  accepted for the full role list on each folder binding; (4) brownfield
  projects created by `terraform-admin` may need a one-off owner grant to
  projects-apply. Residual: bootstrap-apply and organization-apply still hold org
  `iam.securityAdmin` (inherent to managing org IAM); network-hub-apply's org
  `accesscontextmanager.policyAdmin` inherits onto the per-environment scoped
  policies; `envs/gcp/organization` still grants `terraform-admin` env-folder
  roles (`terraform_admin_folder_roles`) when the legacy flag is on.

- **G12 — GCP re-audit hardening (2026-11-06), mock-tested only.** Validate on a
  real org before relying on it:
  (1) **scoped access policies** (`enable_scoped_access_policies`, default on):
  `google_access_context_manager_access_policy` with `scopes = [folders/<env>]`
  per environment is created by organization-apply with org
  `accesscontextmanager.policyAdmin`; confirm creation does not require an
  existing org-level policy, that the workload perimeter in it accepts the host
  and service-team projects, and that the default dry-run ingress/egress rules
  are valid inside a scoped policy;
  (2) **`landingZonePlanViewer`** custom role: every permission must be
  custom-role-supported at org level, and the plan of each root must succeed
  without `roles/viewer` (a missing get/list shows up as a 403 in plan);
  (3) **per-folder projects-apply delegation**: confirm that a folder-level
  conditional `folderIamAdmin` lets projects-apply set the env-folder grants and
  that the org-node grant can be removed (apply order gcp-bootstrap ->
  gcp-organization -> gcp-projects);
  (4) **containment additions** `storage buckets.deleteTagBinding` and
  `cloudkms cryptoKeyVersions.update` (both deny-supported) do not break a
  no-change apply; the `tag_binding_change` / `kms_key_version_disable` watch
  filters match real audit-log method names;
  (5) **PAM** (`enable_pam`, opt-in): entitlement creation at the org node and an
  end-to-end request/approve flow;
  (6) **group-only org admin** (`allow_user_principals_for_break_glass = false`
  by default) removes existing `user:` org/billing admin bindings on the next
  gcp-organization apply: make sure a group (or PAM) holds admin first.
  Not deny-supported, so alert-only: `resourcemanager.tagValueBindings.delete`,
  `tagValues.delete`, `tagKeys.delete`, `cloudkms keyRings.deleteTagBinding`.

- **G14 — GCP guardrail-owner split and 2026 control refresh (2026-11-06),
  mock-tested only.** Validate on a real org:
  (1) **guardrail owner** (`guardrail_owner_mode = "separate"`, default): the
  organization apply SA loses `roles/iam.denyAdmin`. The security-team
  `gcp-guardrails` root (`envs/gcp/guardrails`) authors the deny policies from
  config and applies them as the `<prefix>-guardrails-apply` SA, WIF-bound to
  that workspace by ID only. Confirm a real plan/apply as the guardrails SA, the
  containment tag lookup (`google_tags_tag_key` / `_value`), and that IAM
  accepts the `resource.matchTagId('tagKeys/<n>', 'tagValues/<n>')` condition.
  The PAM-gated `guardrail_owner_members` path (gcloud with
  `deny_policy_specs`) stays for emergencies. Moving an existing policy into the
  new root needs a `terraform import` (UPGRADING.md). Residuals:
  `iam.securityAdmin` on the organization apply SA can still grant itself
  `denyAdmin`; alert-only (`guardrail_role_grant`,
  `guardrail_identity_change`). And **tfc-admin can still repoint
  `gcp-guardrails`** (working directory, VCS branch, team access, variables):
  whoever can apply tfc-admin can undo the security-team-only boundary, so the
  separation of duties also rests on CODEOWNERS for `envs/tfc-admin/**`
  (plan Task 3.5) and on keeping tfc-admin's own approvers apart from the
  platform team;
  (2) **containment additions** (all on the deny-supported list, re-verified
  2026-11): `accessLevels.update/delete/replaceAll`,
  `authorizedOrgsDescs.create/update/delete`, `policies.update/setIamPolicy`
  org-wide; `storage buckets.update`, `cloudkms keyRings.setIamPolicy`,
  `logging buckets.update/deleteTagBinding` tag-scoped. Adding an environment
  (its scoped access-policy IAM) and any audit-bucket config change now need
  break-glass. Confirm the log-bucket tag binding parent
  (`//logging.googleapis.com/projects/<id>/locations/<l>/buckets/<b>`) is accepted;
  (3) **managed constraints** (`prefer_managed_constraints = true`): the
  `iam.managed.*`, `compute.managed.*` and `sql.managed.restrictPublicIp`
  successors replace their legacy constraints in one apply (legacy policy
  deleted, managed created). `iam.allowedPolicyMemberDomains` stays legacy:
  `iam.managed.allowedPolicyMembers` blocks the automatic Owner / Folder Admin
  grants at project/folder creation and Google-owned principals outside the
  org (e.g. `cloud-storage-analytics@google.com`, `billing-export@system.gserviceaccount.com`);
  migrate deliberately with `managed_policies` and explicit `allowedMemberSubjects`;
  (4) **Log Analytics** (default on): org sink to an analytics-enabled log bucket
  plus linked dataset; confirm the bucket-scoped `logging.bucketWriter`
  condition and Log Analytics availability in the chosen location. The bucket
  uses Google-managed encryption unless `log_analytics_kms_key_name` is set;
  (5) **PAB** (`enable_principal_access_boundary`, opt-in) and **org logging
  settings** (`enable_logging_organization_settings`, opt-in) are unapplied;
  (6) **production WIF-by-ID** is now a hard plan failure in gcp-bootstrap;
  (7) **plan-identity residual (N5)**: `roles/run.viewer` and `roles/compute.viewer`
  stay on the plan SAs (Terraform refresh needs `run.services.get` /
  `compute.instances.get`), so a plan identity can read Cloud Run env vars and VM
  metadata. Keep secrets in Secret Manager references, never in env vars or
  startup scripts.

- **A4 — CloudTrail CloudWatch Logs + CIS section-4 alarms, now default ON**
  (`enable_cloudwatch_logs = true`, `modules/aws/security/cloudtrail-org`). The
  full CIS AWS 4.1–4.15 metric-filter set ships with a module-created,
  logs-granted CMK and a KMS-encrypted SNS topic in the management account.
  Mock-tested only. **Validate on a real org**: (1) `CreateLogGroup` succeeds
  with the generated key policy (`logs.<region>` + `kms:EncryptionContext:aws:logs:arn`);
  (2) CloudWatch alarms can publish to the encrypted topic; (3) org-wide
  `unauthorized-api-calls` volume is tolerable (drop it with
  `cloudtrail_cis_alarms_excluded` if not). The security-notifications
  break-glass metric alarm (`cloudtrail_log_group_name`) still assumes a log
  group in the security-tooling account; the trail's group is in the management
  account, so leave that input empty or point it at a copy.
- **A8 — RESOLVED (2026-11-05): vended-log delivery to the log archive.** The
  log-archive bucket now grants `delivery.logs.amazonaws.com` AclCheck + Write
  (`AWSLogs/*`, `bucket-owner-full-control`), both scoped by `aws:SourceOrgID`, and
  the log CMK's default `log_service_principals` includes it, so cross-account VPC
  flow / Network Firewall / Resolver query logs can deliver. Still validate one real
  delivery per log type (mock-tested only).
- **A9 — Network Firewall baseline and tfc-apply boundary are mock-only.**
  (1) The default managed rule-group names are documented by AWS
  (`MalwareDomainsStrictOrder`, `BotNetCommandAndControlDomainsStrictOrder` in the
  domain-list groups; `AttackInfrastructureStrictOrder`); confirm regional
  availability with `aws network-firewall list-rule-groups --scope MANAGED` and
  check the active-threat-defense pricing. (2) The default stateful action is
  log-but-pass (`aws:alert_established`). Move to `aws:drop_established` +
  `aws:alert_established` once egress allow rules exist. (3) Run a full
  security, workload and backup apply under the `tfc-apply-boundary` boundary,
  including a destroy/replace of Config and GuardDuty resources, which the
  boundary deliberately blocks. Use break-glass for those.
- **A10 — AWS escape-hatch hardening (2026-11 re-audit) is mock-only and has
  apply-time consequences.** (1) **Boundary propagation**
  (`enable_apply_boundary_propagation`, default on): `tfc-apply` can only
  `CreateRole`/`AttachRolePolicy`/`PutRolePolicy`/`PutRolePermissionsBoundary`
  on roles carrying `tfc-apply-boundary`, and can never delete a boundary. Every
  `aws_iam_role` created by `tfc-apply` in a member account must therefore set
  `permissions_boundary = arn:aws:iam::<account>:policy/tfc-apply-boundary`.
  `modules/aws/iam/iam-role` supports this; `modules/aws/security/cloudtrail-org`,
  `modules/aws/security/incident-response` and `modules/aws/stages/app-services`
  do **not yet** expose a `permissions_boundary` input, so their role creation in
  member accounts fails until they do (or disable propagation). Residual:
  `iam:UpdateAssumeRolePolicy` on pre-existing unbounded roles that the
  deny-tamper SCP does not protect. (2) **Plan-role data-plane deny**
  (`enable_plan_role_data_read_deny`, default on): plans that refresh data-reading
  resources fail as `tfc-plan`. In-repo this is `envs/aws/workload`'s
  `aws_secretsmanager_secret_version.saas_bridge` (opt-in,
  `enable_saas_secret_bridge`): add its ARN to
  `tfc_plan_role_data_read_exempt_arns`. (3) **Protected KMS key policies are
  break-glass only**: `modules/aws/data/kms-key` now sets the policy at
  `CreateKey` (a `removed` block forgets the old `aws_kms_key_policy` without
  destroying it), but any later key-policy change on a key tagged
  `protected = true` must be applied by break-glass. With `key_policy_admin_arns`
  set, the CreateKey lockout safety check is bypassed, and every listed role
  must already exist in that account. (4) **`dp:*` tags are break-glass only**
  (baseline SCP): opting a resource out of the RCP data perimeter, and
  re-applying a full S3 tag set on a bucket that carries a `dp:*` tag, need
  break-glass. **Validate** that `aws:TagKeys` is populated on
  `s3:PutBucketTagging`/`s3:CreateBucket` and on `kms:CreateKey`/`iam:CreateRole`
  with tags.
- **A11 — break-glass name squatting and pipeline-exempt role tamper (wave-4
  re-audit) is closed, but mock-only, with apply-order consequences.** (1)
  **The SCP role-tamper split has two tiers.** `DenyPrivilegedRoleTampering`
  (OAAR, `stacksets-exec-*`) exempts break-glass only. `DenyStackSetRoleTampering`
  (`tfc-plan`, `tfc-apply` and the break-glass name) exempts break-glass and
  `stacksets-exec-*`. The pipeline is no longer exempt from either. **Validate**
  that the service-managed StackSet execution role is really named
  `stacksets-exec-*` in your org (`stackset_execution_role_names`). Otherwise
  StackSet updates to the tfc and break-glass roles are denied. (2) **Member
  break-glass role** (`enable_member_break_glass_role`, default on in the org
  stage). A sibling StackSet deploys it to the org root. It trusts
  `break_glass_role_arn` and requires MFA by default. **Validate** that MFA
  context survives assuming it from the management break-glass *role*: a
  role-chained session may not carry `aws:MultiFactorAuthPresent`. If it does
  not, trust MFA-authenticated IAM users
  (`member_break_glass_trusted_principal_arns`) or set
  `member_break_glass_require_mfa = false`, because the management role is
  already MFA-gated. A pre-existing role with the same name in a member account
  makes the stack instance fail. Delete it with break-glass first. (3)
  **Security-stage CMK `kms:PutKeyPolicy` now belongs to the member break-glass
  role** (`key_policy_admin_role_name = "break-glass"`). Apply `aws-organization`
  (StackSet) **before** `aws-security`, because KMS rejects a key policy that
  names a non-existent principal. For keys that already exist, the
  key-policy change itself is a `PutKeyPolicy`. The SCP allows that only to
  break-glass, so apply that run as break-glass, or set the role name to `null`.
  (4) **kms-key `ServiceUsage` is account-scoped** (`aws:SourceAccount`) by
  default. Use `service_principal_scope = "organization"` only for keys that
  receive org-wide service writes. **Validate** that SNS, SSM and CloudWatch
  send `aws:SourceAccount` on their KMS calls. (5) **Plan-role reads kept for
  refresh.** `lambda:GetFunction*` (env vars), `ecs:DescribeTaskDefinition`
  (container environment) and `ec2:DescribeInstanceAttribute` (user data) stay
  readable by `tfc-plan`, so secrets must not live in those fields.
- **A12 — standalone AWS workload has no egress (2026-11-06).** With
  `enable_network_hub = false` the spoke VPC has no NAT or TGW default route, so
  Fargate tasks cannot pull the public placeholder image or reach ECR / CloudWatch
  Logs. Add the ECR (`ecr.api`, `ecr.dkr`), `logs`, `secretsmanager` and S3 gateway
  endpoints (modules/aws/network/vpc-endpoints) or a NAT before running services in
  standalone mode.
- **Preset loading from config is GCP-workload only (2026-11-06).** The
  `presets` config key is honoured by `envs/gcp/workload` alone (YAML twin
  `examples/presets/prod-gcp-workload.yaml`, consistency-tested). Other roots
  still need the `-var-file` overlays or TFC variables.

## MODERNIZATION — latest-best-practice gaps (2026 review)

From a 2026 gap analysis of both landing zones against the current AWS SRA and
Google enterprise-foundations / FAST guidance. Both clouds already adhere
closely (see [`landing-zone-conformance.md`](architecture/landing-zone-conformance.md));
these are the specific lags. `SAFE-CONFIG` = a default-off, opt-in code change
that passes `validate` + mock tests; `BEHAVIOR-CHANGING` = needs a real apply or
architectural change and is documented here rather than rushed.

AWS:

- **A5 — single-region backups, no cross-region / air-gapped copy** (MEDIUM,
  BEHAVIOR-CHANGING). `modules/aws/backup/backup-org-policy` writes recovery
  points to one region; there is no `copy_actions` stanza or Logically
  Air-Gapped destination vault. Latest AWS Backup guidance makes cross-region /
  cross-account copy the resilience baseline. Add a `copy_actions` destination +
  second-region vault (needs a real apply). Ref:
  <https://aws.amazon.com/blogs/storage/aws-backup-2025-year-in-review-advancing-recovery-resilience/>
- **A6 — log-analytics primary lags the June-2026 SRA** (MEDIUM, SAFE-DOC done /
  re-plumb BEHAVIOR-CHANGING). The June-2026 SRA names **CloudWatch Unified Data
  Store** the preferred analytics *primary* and Security Lake secondary; this
  zone keeps the S3 WORM archive as the immutable sink (still valid) and treats
  CloudWatch as an out-of-band `awscc` enhancement (A4). Doc framing corrected;
  actually re-plumbing log routing needs a real apply.
- **A7 — Config conformance packs are an empty bring-your-own hook** (MEDIUM,
  SAFE-DOC done / opt-in SAFE-CONFIG). `modules/aws/security/config-org` ships
  the aggregator + pack *resource* but no bundled pack. Optionally ship an
  `Operational-Best-Practices` pack reference defaulting off.

GCP:

- **G6 — Organization Policy custom constraints** — ✅ **SHIPPED opt-in**
  (`custom_org_constraints` on `envs/gcp/organization` → `stages/organization` →
  `org-policy`, default `[]`, mock-tested). CEL resource-shape guardrails now
  wire through to the org node. Remaining follow-ups: migrating the existing
  boolean/list constraints to the `*.managed.*` namespace and adding
  `gcp.restrictNonCmekServices` are still open. Ref:
  <https://docs.cloud.google.com/resource-manager/docs/custom-constraints>
- **G7 — host firewall uses legacy VPC firewall rules, not network firewall
  policies** (HIGH, BEHAVIOR-CHANGING). `modules/gcp/network/network-firewall`
  creates `google_compute_firewall` (legacy per-VPC rules with network tags);
  `stages/host` instantiates it for all tier-to-tier rules. Google directs new
  builds to global/regional **network firewall policies** with IAM-governed
  secure tags. Migration changes rule evaluation → real apply. Ref:
  <https://docs.cloud.google.com/firewall/docs/firewall-policies-overview>
- **G8 — audit-log bucket WORM lock** — ✅ **SHIPPED opt-in**
  (`enable_audit_bucket_lock` on `envs/gcp/organization` → `stages/organization`
  → `cloud-audit-logs`, default `false`, mock-tested). When enabled it applies a
  **locked** retention policy of `audit_log_retention_days` (irreversible — for
  compliance regimes that require tamper-proof retention). Default preserves the
  prior operator-correctable behaviour. **2026-11-05 (M-4):** both audit buckets now
  ship Object Versioning + a 30-day soft-delete policy by default
  (`audit_soft_delete_retention_days`); enabling the lock turns versioning off on
  the audit bucket because GCS forbids versioning together with a retention policy.
- **G9 — IAM Deny policies** — ✅ **SHIPPED opt-in**. New leaf module
  `modules/gcp/iam/deny-policy` (its own mock tests) wired into
  `stages/organization` at the org node via `iam_deny_policies` (on
  `envs/gcp/organization`, default `[]`). Coarse allow-independent backstop that
  blocks sensitive permissions regardless of roles (deny before allow). Inert
  until populated. Ref: <https://docs.cloud.google.com/iam/docs/deny-overview>
  **2026-11-05 (C3):** the built-in `enable_admin_containment` policy now denies
  org-wide sink update/delete, exclusion changes, perimeter update/delete and
  `policies.delete` (the old `accessPolicies.delete` string was not a valid deny
  permission), plus tag-scoped (`containment/protected`) audit-bucket/object/CMEK
  destruction. On in the prod preset. `iam.denypolicies.*` is not deny-supported →
  covered by the `deny_policy_change` control-plane alert instead. Needs real-org
  validation.
- **G10 — SCC is notification-only; no posture service or tier** (MEDIUM,
  BEHAVIOR-CHANGING). `modules/gcp/governance/scc` wires only Pub/Sub findings
  notification. The security posture service (drift detection) needs SCC Premium
  activated org-wide (a paid, out-of-band apply). A `google_securityposture_posture`
  definition could be added as opt-in scaffolding once a tier exists. Target
  **Premium** — the Enterprise tier sunsets 2027-05-21. Ref:
  <https://docs.cloud.google.com/security-command-center/docs/service-tiers>
- **G11 — VPC-SC dry-run-first default** — ✅ **SHIPPED**. Flipped the default
  of `vpc_sc_enable_dry_run` (hub, via `envs/gcp/organization` + `network-hub`)
  and the per-perimeter `enable_dry_run` (host stage) and the workload perimeter
  (`envs/gcp/workload`) from enforce to **dry-run**, matching Google's
  "start in dry-run, promote after validating violation logs" guidance. **Action
  for operators:** promote to enforcement (`vpc_sc_enable_dry_run = false`) once
  the violation logs are clean — dry-run gives no exfiltration protection, so do
  not leave a production perimeter in dry-run. Ref:
  <https://docs.cloud.google.com/vpc-service-controls/docs/dry-run-mode>
  **2026-11-05 (SOTA M):** the vpc-sc module now supports an enforced `status`
  plus a staged dry-run `spec` (`dry_run_restricted_services` /
  `dry_run_ingress_policies` / `dry_run_egress_policies`), and the workload and
  network-hub roots warn (check blocks) when a prod-like environment has no
  perimeter or a dry-run one.
- **G12 — CIS GCP Foundations gaps (2026-11-05)** — ✅ **SHIPPED**, mock-tested
  only. Validate on a non-prod org before you cite these to an auditor.
  (a) CIS 2.4–2.11 log-based metrics and alerts (`cis_log_metrics` in
  `modules/gcp/monitoring/control-plane`, `enable_cis_log_metrics`, default on)
  live in the audit project. The aggregated org sink feeds them every project's
  Admin Activity. CIS and SCC Security Health Analytics check each project for
  its own metric, so per-project findings stay open: record the central design
  as a compensating control. The 2.5 and 2.6 metrics duplicate the
  `audit_config_change` and `custom_role_change` log-match watches. Remove one
  of each pair if the double notification is noise.
  (b) `compute.requireOsLogin` is enforced at the org node (`enforce_os_login`).
  Exempt folders with `os_login_exempt_environment_keys`. **Behaviour change:**
  VMs that rely on metadata SSH keys lose SSH access unless their folder is
  exempt.
  (c) Artifact Registry scanning: the Container Scanning API is enabled, and
  DOCKER repositories are set to `INHERITED`. Scanning is billed per image.
  (d) VM backup and patching in `envs/gcp/workload`. `enable_vm_backup_policy`
  (default on) only creates snapshot policies, so attach disks to them.
  `enable_os_patch_management` (default on) runs a weekly patch job; the
  workload apply SA holds `roles/osconfig.patchDeploymentAdmin` via the
  gcp-bootstrap `workload_folder_roles`.
- **KMS Autokey / HSM-for-sensitive** (LOW, SAFE-CONFIG, future). No Cloud KMS
  Autokey; CMEK defaults to `SOFTWARE` protection (HSM is per-key selectable).
  Autokey (GA 2024, dedicated-project storage GA 2026) and HSM-by-default for
  audit/SCC keys are maturity improvements, not deficiencies.
- **Flat folder tree** (LOW, BEHAVIOR-CHANGING, documented divergence). Folders
  are parented directly at the org (one per env + shared), not under a
  prod/nonprod grouping layer. Deliberate simplification for a smaller org;
  a grouping layer would let tier-level guardrails inherit by folder.

## PREVIEW — opt-in, default-off, not yet validated (mock-tested only, no on-path coverage)

Enable only after validating in a real/test org. Each defaults to prior behaviour.

- **G4 — dedicated logging project** (`logging_project_id` +
  `logging_project_number`, `modules/gcp/stages/organization`). The audit bucket,
  BigQuery dataset, audit CMEK keyring (`<prefix>-audit-cmek`, granted to the
  logging project's own service agents — no cross-project KMS grant) and the
  control-plane alerts all move there. The project must NOT be owned by the
  automation SA. Decide before the first apply (KMS keys are undeletable).
- **G5 — VPC-SC perimeter expansion** (`vpc_sc_additional_restricted_services`,
  `vpc_sc_ingress_identities`, `modules/gcp/stages/network-hub`). Set the ingress
  identity BEFORE expanding services or an enforced apply is blocked.
- **A3 — dedicated Identity Center account** (`identity_account_id`,
  `modules/aws/stages/security`). Point at a real dedicated identity account.

## Capability parity (2026 review)

A capability-table audit found several `—` cells that were **real missing
modules**, not true "not applicable". Closed by adding modules on the lagging
side (all mock-tested, secure defaults):

- **Load balancing** — added `modules/aws/network/load-balancer` (ALB/NLB) ↔ GCP `network/internal-lb`.
- **API gateway** — added `modules/aws/network/api-gateway` (API Gateway v2) ↔ GCP `network/api-gateway`.
- **CDN / edge** — no new module; corrected a **doc mis-mapping**: AWS CloudFront already lives in `modules/aws/security/edge-security`, not `—`.
- **Private CA** — added `modules/gcp/governance/private-ca` (CAS) ↔ AWS `data/private-ca`.
- **Scheduled backups** — added `modules/gcp/backup/backup-plan` (snapshot schedules) ↔ AWS `backup/*`.
- **Metrics / dashboards** — added `modules/aws/ops/cloudwatch` (alarms + SNS + dashboard) ↔ GCP `monitoring/*`.
- **Image registry** — added `modules/aws/data/ecr` ↔ GCP `artifact-registry`.
- **Hybrid VPN** — added `modules/aws/network/vpn` (Site-to-Site, IKEv2/AES-GCM, TGW or VGW) ↔ GCP `network/vpn` (HA-VPN).
- **Fleet / patch management** — added `modules/gcp/ops/os-config` (VM Manager patch deployments) ↔ AWS `ops/systems-manager`.

**Remaining `—` cells are intentional asymmetries, not gaps:**

- **GCP IPAM** — Google has no distinct IPAM product; CIDR planning is per-project subnets. AWS IPAM has no GCP analogue to modularize.
- **Firebase** (`modules/gcp/firebase/project`) — GCP-specific; no AWS equivalent (Amplify is a different, niche product).
- **NAT / VPC flow logs** — on AWS these are attributes of the `network/vpc` module (native), whereas GCP exposes discrete `network/nat` and `network/vpc-flow-logs` modules. Same capability, different modularization; not a missing module.
- **GCP service-quotas** — GCP quota management (consumer overrides) differs enough that no parity module is warranted today; AWS `governance/service-quotas` has no clean GCP mirror.

## BLOCKED — waiting on provider capability

- **S1 — Supabase new API keys.** The `supabase/supabase` provider (`~> 1.0`)
  does not yet expose `sb_publishable_`/`sb_secret_` on `supabase_apikeys`; the
  module uses the legacy JWT keys, which Supabase deprecates end-2026. Expose the
  new keys as outputs once the provider supports them.
- **S4 — RESOLVED (2026-11-05).** The Terraform floor is now `~> 1.11` and secrets use
  write-only arguments, so they never enter plan or state: GCP Secret Manager
  (`secret_data_wo`), Cloud SQL users (`password_wo`), Aurora master password
  (`master_password_wo`), sensitive TFC variables (`value_wo`) and sensitive Vercel env
  vars (`value_wo`, supported by vercel 4.8.2). Remaining: `supabase_project.database_password`
  (no write-only argument in the supabase provider yet) and the Vercel change-detection
  fingerprint, which is an unsalted SHA-256 of the env values.
  Ephemeral inputs (2026-11-06): `rds-aurora.master_password` is `ephemeral = true`;
  `cloud-sql` adds an ephemeral `user_passwords` map (opt in per user with
  `ephemeral_password = true`) and `secret-manager` an ephemeral
  `ephemeral_secret_values` map (opt in per secret with `ephemeral_value = true`) —
  the opt-in flags exist because an ephemeral value cannot drive `for_each`, so the
  legacy sensitive inputs stay for backward compatibility. Vercel env-var inputs
  cannot be ephemeral: they also feed the `for_each` keys and the stored fingerprints.

- **S-M3 — SaaS bridge values pass through workload state (waiting on
  Terraform 1.17 test mocking).** With `enable_saas_secret_bridge`, the bridged
  secret versions are write-only: `secret_string_wo` (AWS) and the
  secret-manager module's `secret_data_wo` (GCP). The saas `bridge_version`
  output (`saas.bridge_rotation`) drives `*_wo_version`. **Residual:**
  `envs/aws/workload` and `envs/gcp/workload` still read the Supabase
  service-role key and database password through
  `data "terraform_remote_state" "saas"`, and a data source's result is stored
  in the workload's state. Task 3.6 closes this. It replaces that read with
  `ephemeral "tfe_outputs"` (tfe >= 0.65), keeps a non-ephemeral
  `data "tfe_outputs"` for `bridge_version`, and authenticates with the
  hand-created `saas-outputs-reader` team token (`saas_outputs_reader_team_id`,
  already granted). It waits on the test toolchain. Terraform 1.14, the CI pin,
  cannot test a root that contains an ephemeral resource offline:
  `mock_provider` rejects every ephemeral resource type at validation, even at
  `count = 0`. `override_resource`, `override_data` and `override_module` cannot
  target one, and a real `tfe` provider contacts the HCP Terraform host when it
  is configured. Terraform 1.17 mocks ephemeral resources.
- **SaaS secrets stay in `saas-*` state (provider limitation).**
  `supabase_project` has no write-only `database_password`, so the creation-time
  password is in the `saas-<name>` state and its `supabase_database_password`
  output. The service-role key is in the same state as a data-source result and
  an output. Access to that state is limited to the `saas-*` workspace's
  writers, the listed `extra_remote_state_consumers` and the
  `saas-outputs-reader` team (outputs only). Rotation: see
  [saas-bootstrap](runbooks/saas-bootstrap.md#bridging-secrets-to-a-workload-and-rotating-them).

## DECISION — needs a human call

- **Behaviour-changing security defaults** (not applied, would change posture):
  packet-mirroring default mirrors all traffic; vpc-peering exports public-IP
  subnet routes; the shared VPC-endpoint policy is `Action="*"`.
- **GCP VPN / Interconnect exposure.** `modules/gcp/stages/net-hub` wires
  `network/vpn` (`var.vpn`) and `network/interconnect`, but
  `modules/gcp/stages/network-hub` does not pass them through, so they cannot
  be set from `envs/gcp/network-hub` or `config/landing-zone.yaml`. Pending
  Task 4.4.
- **`host` stage decomposition.** `modules/gcp/stages/host` (~2,000 LOC) is
  large-but-cohesive; a targeted split (firewall / egress / advanced sub-stages)
  is optional maintainability work, not a bug.
- **Toolchain currency automation.** Dependabot covers both GitHub Actions and
  the `terraform` ecosystem (`directories: ["/**"]`, one grouped weekly PR,
  labelled for review, never auto-merged); the repo pins keep proposals inside
  the current provider major. Open call: switch to Renovate only if grouped,
  compatibility-aware *major* bumps or `required_version` bumps are wanted.
