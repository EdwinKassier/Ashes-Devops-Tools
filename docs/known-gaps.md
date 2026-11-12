# Known Gaps & Preview Features

A single, honest inventory of things that are **not yet done, not yet validated,
or deliberately deferred**. This exists so `CLAUDE.md` can stay a doc of
always-true authoring rules instead of a running bug list, and so a new
maintainer has one place to see what's aspirational vs load-bearing.

Status legend: **OPEN** (a real gap to fix) · **PREVIEW** (code shipped, opt-in,
default-off, not yet validated against a real apply) · **BLOCKED** (waiting on an
upstream/provider capability) · **DECISION** (needs a human call before action).

## OPEN — validate before relying on

- **GCP Cloud NAT egress route is mock-tested only.** `net-hub` / `net-spoke`
  now add a `0.0.0.0/0` route to the default internet gateway when NAT is on
  (`tiered-vpc` deletes the default route at creation). Confirm in the sandbox
  that a VM with no external IP in the private tier reaches the internet through
  Cloud NAT, and that the database tier still cannot.
- **IAP through the hub hierarchical policy is mock-tested only.** Confirm in
  the sandbox that `gcloud compute ssh --tunnel-through-iap` reaches a
  private-tier VM, and that SSH from any other source is still denied.
- **Member-account backup vault first apply is unproven.** Confirm that the
  updated Backup service-role StackSet creates `org-backup-vault` in a
  Workloads-OU account, and that the next daily BACKUP_POLICY job completes.
- **The customer managed key member backup vault is mock-tested only.** Mock
  tests prove the StackSet templates, not AWS Backup or KMS behaviour. With
  `member_backup_vault_encryption = "cmk"` (or `compliance.backup`), confirm
  in the sandbox that the StackSet execution role creates the key tagged
  `protected = true` under the deny-tamper SCP, that `org-backup-vault-cmk` is
  encrypted with it, that the DR StackSet does the same in
  `member_backup_dr_region`, and that a copy job from that vault to the backup
  account succeeds with the `BackupAccountCopy` key-policy grant.
- **The central backup copy is mock-tested only (CMP-1, ARC-8).** Mock tests
  prove the BACKUP_POLICY document, the copy vault, its key policy and the
  wiring, not AWS Backup behaviour. With
  `compliance.backup.copy_to_central_vault: true` (and `dr_region`), confirm in
  the sandbox: the `aws-backup` management apply role sets
  `isCrossAccountBackupEnabled`; the backup account's `tfc-apply` role creates
  the `backup-copy-vault` key (tagged `protected = true`, break-glass as the
  only `kms:PutKeyPolicy` holder) and `org-backup-copy-vault` with it; a daily
  job writes to `org-backup-vault-cmk` and the copy jobs to the copy vault and
  to the DR vault succeed for each resource type (EBS on a customer managed key,
  EC2, RDS, Aurora, S3, DynamoDB, EFS); the copy vault key grants are enough
  for copy-in and for restores (the key admits backup-account principals only
  through Backup, EC2, RDS, S3, DynamoDB and EFS); and the restore-testing
  plan restores RDS and Aurora without restore metadata overrides. With
  `copy_vault_notification_topic_arn` set, also confirm which failure events
  reach the topic: that a failed restore-testing restore arrives as
  `RESTORE_JOB_FAILED`, and whether a failed copy does (copy jobs into the copy
  vault start in the member account, so it may be reported on the source vault
  only). Do this in a
  throwaway vault first or within `changeable_for_days`: the lock cannot be
  removed after that window.
- **The pipeline can still overwrite the copy vault's lock and access policy
  during `changeable_for_days`.** The tfc-apply boundary
  (`tfc-oidc-baseline` `protected_backup_vault_names`, statement
  `DenyProtectedBackupVaultUnlock`) denies `DeleteBackupVaultLockConfiguration`,
  `DeleteBackupVaultAccessPolicy` and `DeleteBackupVault` on
  `org-backup-copy-vault`, so only break-glass can remove them. It cannot deny
  `PutBackupVaultLockConfiguration` or `PutBackupVaultAccessPolicy`: the
  aws-backup apply that creates the vault calls both, and IAM has no condition
  key that tells the first call from a later overwrite. Until the window ends, a
  compromised tfc-apply could lower `min_retention_days` or replace the access
  policy so that copies stop arriving. After the window, AWS rejects every lock
  change. Three more limits: the boundary caps only `tfc-apply`, so a run that
  assumes `OrganizationAccountAccessRole` (the aws-backup legacy path without
  TFC dynamic credentials) or a local administrator is not covered; the
  deny-tamper SCP does not carry the same deny, so no SCP covers those
  principals; and the protection exists only after aws-organization
  applies the updated StackSet. Mitigation: keep `changeable_for_days` short
  and watch `PutBackupVaultLockConfiguration` and `PutBackupVaultAccessPolicy`
  in CloudTrail for the backup account during the window. Confirm in the
  sandbox that tfc-apply gets AccessDenied on the three Delete calls and that
  the first aws-backup apply still creates the lock and the policy.

- **Organization policy size quotas are checked on the rendered string only
  (ARC-18).** `modules/aws/governance/organization-policy` fails the plan when
  a policy is longer than the AWS Organizations quota for its type: SCP 10,240
  characters, RCP 5,120, AI services opt-out 2,500, other types 10,000 (AWS
  documentation checked on 2026-11-12). With every option that adds statements
  turned on and long names, mock tests measure `scp-deny-tamper` at 6,485
  characters and `rcp-data-perimeter` at 2,811. AWS counts whitespace when a
  policy is saved through the API, and the module sends the content as
  rendered. A real `CreatePolicy` and `UpdatePolicy` in the sandbox is still
  the proof that AWS counts the same way.

- **The explicit-CIDR IPAM default for spoke VPCs needs the sandbox proof (ARC-1).**
  `modules/aws/network/vpc` requests `cidr_block` from the IPAM pool by default.
  Mock tests prove the planned shape only. A real `hashicorp/aws` 6.72.0 plan
  with a hand-made state and no API calls showed no change for an existing
  netmask-shape VPC (`ignore_changes = [ipv4_netmask_length]`). Still to
  confirm: a plan of `aws-workload-dev` against its real state after the
  upgrade shows no VPC change, and an e2e apply allocates the requested block
  from a real IPAM pool and creates a subnet inside it.

- **The hub VPC IPAM reservations need the sandbox proof (ARC-1).**
  `modules/aws/stages/network-hub` reserves each static hub VPC range in the
  regional IPAM pool (`aws_vpc_ipam_pool_cidr_allocation.hub_static`). Mock
  tests prove the planned reservations only. Still to confirm: an aws-network
  apply creates both reservations in a real pool, IPAM then refuses a spoke
  that requests a hub range, and the hub VPCs are unaffected. The aws-network
  plan cannot detect a spoke that already holds a hub range, because no
  `hashicorp/aws` 6.72.0 data source lists pool allocations; that conflict
  fails the apply of the reservation (recovery in `UPGRADING.md`).

- **AWS deployment outside eu-west-2 needs the sandbox proof (ARC-3).**
  aws-network and aws-workload resolve availability zones from
  `availability_zone_ids` (variable or config) or the region, and
  `modules/aws/network/vpc` fails the plan on a zone from another region. Mock
  tests prove the resolution order, the ID-to-name mapping and the plan
  failures only. Still to confirm: with `org.regions.aws` set to a region other
  than eu-west-2 (for example us-east-1) and no zone input, aws-network and one
  aws-workload apply with every subnet in that region; and with
  `aws.network.availability_zone_ids` set, the hub and spoke subnets report the
  same `AvailabilityZoneId` in both accounts.

- **Spoke resolution of the internal zone needs the sandbox proof (ARC-2).**
  `gcp-network-hub` binds the `internal-root` zone to the hub VPC as well as
  `dns-vpc-core`, and `gcp-projects` grants each workload apply SA
  `roles/dns.peer` on the shared folder. Mock tests prove the planned binding
  and grants only; they cannot prove resolution. Still to confirm: the
  `gcp-workload-dev` apply creates `internal-peering` without a permission
  error, and a VM in the dev spoke resolves a record in `internal-root` (for
  example `dig +short <name>.<internal domain>` returns its A record, not
  NXDOMAIN).

- **Vercel `resource_config` first apply is unproven.** `modules/vercel/project` now sets
  `resource_config.function_default_regions` instead of the deprecated
  `serverless_function_region`. Confirm in the sandbox that the update is in place and that the
  first-time `resource_config` does not reset `fluid`, `function_default_cpu_type` or
  `function_default_timeout` on an existing project.
- **Upstream applies auto-apply non-prod workloads.** Workload
  `gcp-workload-<env>` / `aws-workload-<env>` workspaces whose environment sets
  `is_production: false` (the flag is required on every environment) get
  `auto_apply_run_trigger` and `queue_all_runs`
  (`enable_nonprod_workload_auto_apply`; the null default turns it on only while
  the policy sets, and so `destroy_guard`, are attached). The trust change: a
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

- **AWS spoke TGW routing is mock-tested only, and needs a manual hand-off.**
  Until this release no spoke attachment was accepted, associated or
  propagated, so workload spokes had no egress, no egress replies and no
  on-premises path. aws-network now wires each spoke listed in
  `aws.network.spoke_attachments` (accept, associate with `prod`/`nonprod`,
  propagate into `inspection`, plus `inspection 0/0 → egress` and
  `shared <top_cidr> → inspection`). Open:
  - the hand-off is manual: copy each `aws-workload-<env>` output
    `tgw_attachment_id` into the config and apply aws-network. A spoke not
    listed has no routing (no run trigger or discovery closes the loop; the TGW
    owner cannot read tags the workload account set on its attachment);
  - **with `enable_network_firewall = false` (the `starter` profile) wired
    spokes still have no egress:** prod/nonprod default to the inspection
    attachment, and without the firewall the inspection VPC's tgw tier has no
    forwarding route. Route those segments to egress (or keep the firewall) is a
    design decision not yet made;
  - prod↔nonprod flows are routable *through* inspection (the inspection
    table knows every spoke); only the Network Firewall policy separates the
    segments. Alert-only mode passes them. Separate per-segment inspection
    tables would enforce it at the routing layer;
  - **validate in the sandbox:** the accepter on a `pendingAcceptance`
    attachment, the association of a cross-account attachment, end-to-end
    egress and reply through the firewall (appliance mode), and on-premises →
    spoke over the VPN.

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
  The tfc-admin workspace's own access is limited to owners and the tfc-admin
  team, but **any other team holding organization-level `manage_workspaces`
  can still queue and apply tfc-admin** (that permission spans every
  workspace). Keep that permission on the tfc-admin team alone.

- **Org-trail selector changes are detected, not prevented.** The
  aws-security management apply role keeps `cloudtrail:PutEventSelectors` /
  `PutInsightSelectors`, because `aws_cloudtrail` calls them on create. A
  selector change (for example, dropping management events) is caught only
  by the `org-guard-alerts` EventBridge rule. That rule is in us-east-1 plus
  forwarders in every other enabled region, and it is owned by
  `aws-organization`. The CIS 4.5 alarm does not match selector calls. With
  `aws.enable_cloudtrail_delegated_admin` the management role loses every
  trail write and the trail is managed from security tooling, where the SCP
  denies selector and trail updates to every principal except the pipeline
  roles (`tfc-apply`, `OrganizationAccountAccessRole`, `stacksets-exec-*`) and
  break-glass. Those exempt principals can still change selectors: that stays
  detect-only, through the `sec-notify-org-trail-tamper` rule in security
  tooling (see the CloudTrail delegated-admin item under PREVIEW). The rules
  and forwarding are mock-tested
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
  VPC if it then moves to an IPAM pool. `gcp-workload`'s `module "environment"`
  must consume `local.hub_vpc_peerings` / `local.hub_dns_zones` / `local.org_id`.
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
  (3) the projects-apply `modifiedGrantsByRole` delegated grant works on a
  real folder. IAM accepts at most 10 roles in one `hasOnly()` list, so
  gcp-organization (and the legacy org-level binding in gcp-bootstrap) binds
  one condition per 10 roles: the default lists give 3 bindings on each
  environment folder (27 roles) and 2 on the shared folder (13 roles).
  gcp-projects turns off google provider batching so that each folder IAM
  change is its own `setIamPolicy` call and matches one chunk. Still open:
  a real gcp-organization apply that IAM accepts, and a real gcp-projects
  apply that grants roles from every chunk; (4) brownfield
  projects created by `terraform-admin` may need a one-off owner grant to
  projects-apply. Residual: bootstrap-apply still holds an unconditional org
  `iam.securityAdmin` (inherent to managing org IAM), and organization-apply a
  role-conditioned one (see the SEC-3 items in the WS3 section); network-hub-apply's org
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
  new root needs a `terraform import` (UPGRADING.md). The organization apply
  SA can no longer grant itself `denyAdmin`: its org `iam.securityAdmin` is
  role-conditioned and it holds no `folderAdmin` (remaining paths: the SEC-3
  items in the WS3 section; `guardrail_role_grant` and
  `guardrail_identity_change` alert as defence in depth). And **tfc-admin can still repoint
  `gcp-guardrails`** (working directory, VCS branch, team access, variables):
  whoever can apply tfc-admin can undo the security-team-only boundary, so the
  separation of duties also rests on CODEOWNERS for `envs/tfc-admin/**` and
  `config/tfc-workspaces.yaml` (both security co-owned; the committed file
  cannot set `gcp-guardrails` variables) and on keeping tfc-admin's own
  approvers apart from the platform team;
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
  account, so leave that input empty or point it at a copy. With
  `aws.enable_cloudtrail_delegated_admin` the trail's group is in security
  tooling and the alarm uses it by default.
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
  The security, backup, workload and app-services stages derive that ARN from
  `tfc_apply_boundary_policy_name` (default `tfc-apply-boundary`) and set it on
  the roles they create. Pre-existing unbounded roles, groups and users are
  closed in the boundary too: `DenyTrustPolicyUpdates`
  (`enable_apply_trust_update_lock`, default on) denies
  `iam:UpdateAssumeRolePolicy` on every role, because IAM does not evaluate
  `iam:PermissionsBoundary` for that action. `DenyForeignPolicyVersioning`
  denies new versions of customer-managed policies outside the `/tfc-managed/`
  path. `DenyGroupUserAndLoginProfileEscalation` denies group and user
  policies, group membership and console password changes. Consequence: a
  trust change on an existing role (for example a new GitHub ref or
  environment on an app-services deploy role, a new `trust_policy` in
  `modules/aws/iam/iam-role`, or a new forensics account on the
  incident-response snapshot role) fails as `tfc-apply`. Apply it as
  break-glass, or replace the role (`-replace=<address>`; CreateRole sets the
  new trust). **Validate** these statements in a sandbox account. (2)
  **Plan-role data-plane deny**
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
  must already exist in that account. Retargeting or deleting the alias of a
  protected key is break-glass only as well (`kms:UpdateAlias`/`kms:DeleteAlias`
  in the boundary and the deny-tamper SCP). KMS authorizes an alias change on
  the alias and on the current and the target key, so the tag condition matches
  through the key. **Validate** that in a sandbox account. (4) **`dp:*` tags
  are break-glass only**
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

## OPEN — residual items from the 2026-11-11 audit remediation

[The audit](audit/2026-11-11-expert-audit.md) has the findings. These parts are not closed:

**Phase 1 complete (2026-11-12).** Phase 1 of [the remediation plan](moai/plans/2026-11-11-dd-score-max/README.md) is done in code. Phase 2 is next. The mock-tested items below still need the sandbox.

- **Validate in the sandbox (mock-tested only):**
  - GCP rejects a peering to a network that does not exist yet. The hub-side
    `hub-to-<env>` peering design relies on it, and on the `google_compute_networks`
    attribute `networks`.
  - The log-archive CloudTrail grants now also require `aws:SourceArn` =
    `arn:<p>:cloudtrail:*:<management>:trail/*`. Confirm one real delivery,
    including from a delegated-admin trail.
  - Server access logs arrive in the companion `<archive>-access-logs` bucket.
  - A no-op folder IAM write passes the `modifiedGrantsByRole` delegation condition.
  - The hub Secure Web Proxy (preview): the PSC endpoint, the FQDN allowlist,
    and a spoke private tier with no Cloud NAT.
- **An enforced environment perimeter admits the environment's own plan and
  apply SAs (ARC-13).** Mock-tested only. gcp-projects publishes them in
  `environment_config.<env>.automation_identities`, and the environment stage
  adds one ingress rule for them: any source, every resource in the perimeter,
  the restricted services only (enforced plus staged dry-run). Prove it in the
  sandbox: enforce the dev perimeter and run a plan and an apply. Other callers
  (CI, app deploy SAs, cross-project readers) still need rules of their own
  (`examples/vpc-sc`).
- **GKE Autopilot still runs in the Shared VPC host project** in production.
- **The Secure Web Proxy has no TLS inspection.** Rules match on host name only.
- **AWS data-plane alarms are not implemented:** TGW `PacketDropCountBlackhole` /
  `NoRoute`, Network Firewall `DroppedPackets`, Site-to-Site VPN `TunnelState`.
- **The tfc-plan API-key deny cannot use `plan_role_data_read_exempt_arns`.** A
  stack that plans REST API keys must turn the deny off.
- **The deny-tamper SCP does not cover an external apply boundary** set through
  `apply_permissions_boundary_arn`.
- **Security Lake in extra Regions** uses S3-managed keys unless
  `additional_region_kms_key_ids` names a regional key.
- **`tfc_admin_guard` cannot see a workspace removed from a policy set** when the
  same plan creates a workspace (`workspace_ids` is unknown).
- **gcp-guardrails state is backed up only** if the security team grants the
  state-backup team access by hand.
- **One `config/landing-zone.yaml` edit still queues a plan on every workspace.**
  Trigger patterns are now scoped to each root's modules, but the file itself is
  shared. Splitting it per layer and environment is open.
- **Services still live in the workload root.** [ADR 0015](adr/0015-team-owned-app-stacks.md)
  (team-owned app stacks) is Proposed.
- **`aws/stages/organization` is still one large stage.** [ADR 0016](adr/0016-split-aws-organization-stage.md)
  is Proposed.
- **Stage tests:** `aws/stages/security` and the gcp-organization CMEK path now
  have real wiring suites. Other stages still rely on `override_module`, and no
  stage has a real-apply e2e test.
- **Root config suites without assertions:** aws/security, gcp/bootstrap,
  gcp/guardrails, gcp/network-hub, gcp/organization.
- **gcp-network-hub has three untyped (`any`) inputs** without unknown-key checks.
  An object type drops undeclared keys silently, so map inputs here use `any`
  plus key validation instead.
- **CI hardening:** `check-jsonschema` is still installed without hashes
  (`terraform-plan.yml`). harden-runner is still in audit mode for docs-bot,
  e2e-sandbox and state-backup.
- **Release:** one SemVer for all 125 modules, no signed tags or build provenance.
- **Bus factor:** one maintainer. Code cannot fix this; see the operator items below.
- **Release tags are mutable.** Published examples pin `?ref=vX.Y.Z` tags
  (release-please bumps them) and Checkov CKV_TF_1 is skipped on them. Release
  tags are not yet protected as immutable. Fix: add a tag ruleset (WS5 Task 8).
- **Plain HTTP load-balancer listener.** `modules/aws/network/load-balancer`
  accepts a plain HTTP listener with forward or fixed-response. Enforcing
  `redirect-https` on application load balancers is a breaking change planned
  outside Phase 0.
- **Real-cloud checks fail on schedule until the sandbox is funded (2026-11-11).**
  Drift detection and sandbox e2e fail on schedule while their credentials and
  variables are unset (plan decision D10). The owner can opt out with the
  repository variable `REAL_CLOUD_CHECKS_OPT_OUT=true`; the variable is not set yet.
  Once set, scheduled runs end without failing and show warnings that the checks
  did not run: drift detection reports "did NOT run" and a summary that says drift
  is unmonitored, and sandbox e2e reports "E2E NOT run". Manual and `e2e`-label
  e2e runs still fail when unconfigured. Remove the variable once the sandbox is
  funded (WS5 Task 30).
- **CMP-20: the org stage `allowed_regions` default mixes EU and US.** The default in
  `modules/gcp/stages/organization/variables.tf` allows `europe-west1`, `europe-west2` and
  `us-central1`. Narrowing it is a breaking change (the location policy would deny the
  dropped regions for callers that rely on the default), so it is deferred out of Phase 0.
  The deployable root reads `gcp.allowed_regions` from `config/landing-zone.yaml`.
- **The AWS stage defaults for `availability_zones` still name `eu-west-2`.**
  The `availability_zones` defaults in `modules/aws/network/vpc`,
  `modules/aws/stages/network-hub` and `modules/aws/stages/workload` are
  `eu-west-2a` and `eu-west-2b` (the VPC module also has `eu-west-2c`). The
  deployable roots always pass resolved zones. A direct stage or module caller
  in another region must set `availability_zones`, or the plan fails at the VPC
  precondition (`availability_zones` must start with the VPC region).

## OPEN — operator actions and items carried from archived audits

`docs/audit/archive/` holds superseded audits; this file is the single list of open items.

- **Operator, GitHub and HCP side (cannot be done from code):**
  - Create real GitHub teams with at least 2 humans between them, and render
    `.github/CODEOWNERS` for the fork (`scripts/init-landing-zone.sh --codeowners`;
    the upstream file keeps `your-org` placeholders, and the meta-lint job fails on
    a fork while any remain).
  - Enable required code-owner review and `enforce_admins` on the default branch,
    and make `Validation Summary` a required check (`docs/guides/BRANCH_PROTECTION.md`;
    `make required-checks-live` diffs the live settings).
  - Create the release GitHub App, set the variable `RELEASE_APP_ID` and the secret
    `RELEASE_APP_PRIVATE_KEY` in the `release` environment
    (`docs/guides/CI_SECRETS.md#release_app`; `release.yml` requires them), so later
    releases come from release-please.
- **No IAM policy-simulation harness.** SCP, RCP and boundary conditions are
  asserted against rendered JSON only; nothing in `scripts/` or CI runs
  `SimulatePrincipalPolicy`. Real-cloud proof comes from the sandbox (ADR 0006).
- **Workload runtimes not yet modularised.** There are no modules for EKS, Lambda,
  Cloud Functions, a cache tier (ElastiCache or Memorystore) or NoSQL (DynamoDB or
  Firestore). The golden paths cover Cloud Run, GKE Autopilot, ECS Fargate,
  Cloud SQL and Aurora only.

## MODERNIZATION — latest-best-practice gaps (2026 review)

From a 2026 gap analysis of both landing zones against the current AWS SRA and
Google enterprise-foundations / FAST guidance. Both clouds already adhere
closely (see [`landing-zone-conformance.md`](architecture/landing-zone-conformance.md));
these are the specific lags. `SAFE-CONFIG` = a default-off, opt-in code change
that passes `validate` + mock tests; `BEHAVIOR-CHANGING` = needs a real apply or
architectural change and is documented here rather than rushed.

AWS:

- **A5 — cross-account and cross-region backup copy is opt-in and unproven**
  (MEDIUM, PREVIEW). By default `modules/aws/backup/backup-org-policy` writes
  recovery points to one vault in one region of each member account, on the
  AWS managed key, so backups share the workload account's blast radius.
  `compliance.backup.copy_to_central_vault: true` (aws-organization, then
  aws-backup) adds `copy_actions` to a CMK-encrypted, Compliance-locked copy
  vault in the backup account, and `compliance.backup.dr_region` adds a copy to
  a member vault in a second region. Still to validate: copy job success for
  each resource type, restore testing metadata for RDS and Aurora, and the
  fact that EBS volumes on the AWS managed `aws/ebs` key cannot be copied across
  accounts. No Logically Air-Gapped vault is offered. Ref:
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
- **G7 — host firewall defaults to legacy VPC firewall rules** (HIGH,
  BEHAVIOR-CHANGING) — ⚠️ **module shipped opt-in, roots not wired.**
  `tiered-vpc` (and the `net-hub` / `net-spoke` compositions) take
  `firewall_mode = legacy | both | policy`: `both` adds one global **network
  firewall policy** whose rules select tiers by subnet CIDR beside the legacy
  tag-based rules; `policy` removes the legacy rules
  ([`gcp-firewall-policy-migration.md`](runbooks/gcp-firewall-policy-migration.md)).
  Default stays `legacy`, mock-tested only. Open:
  - no deployable root (`gcp-network-hub`, `gcp-workload-<env>`) exposes
    `firewall_mode` yet, so an estate cannot select it without a code change;
  - in `policy` mode the legacy `deny_all` rule's logging is lost (the implied
    deny is not logged);
  - the internal-load-balancer policy rule is untargeted (no
    `target_secure_tags`); Cloud Run direct VPC egress cannot carry secure tags;
  - in `both` mode an explicit `firewall_priority` no longer sets the policy
    rule's priority (undocumented);
  - runbook wording: step 2 says "before step 1", and the `gcloud` filter
    quoting (`~ -db-`) needs a check;
  - the migration has not run in the sandbox.
  Ref: <https://docs.cloud.google.com/firewall/docs/firewall-policies-overview>
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
  **SEC-8:** a production gcp-workload environment with no perimeter or a
  dry-run one now **fails the plan** unless `production_vpc_sc_dry_run_waiver`
  names a reason and an expiry date (`YYYY-MM-DD`, UTC) that has not passed.
  An expired waiver fails the plan again. The hub keeps its check-block
  warning.
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

- **Organization trail managed by the CloudTrail delegated administrator**
  (`aws.enable_cloudtrail_delegated_admin`, ADR 0012,
  [runbook](runbooks/aws-cloudtrail-delegated-admin-migration.md)). Mock-tested
  only; not sandbox-proven, so the scaffolder leaves it off.
  Verified against AWS documentation (2026-11-07):
  - The management account owns a trail a delegated admin creates, and removing
    the delegated admin deletes none of its trails.
  - A delegated admin can attach a CloudWatch Logs group only through
    `CreateTrail` / `UpdateTrail`, and the group and its role must exist in the
    calling account.
  - Only a CloudTrail-API registration creates the CloudTrail service-linked
    roles; `RegisterOrganizationDelegatedAdmin` fails with
    `AccountRegisteredException` on an account already registered.
  - For an organization trail, `aws:SourceAccount` is the management account,
    and the KMS encryption context is the trail ARN in the management account.
    The log CMK's `kms:EncryptionContext:aws:cloudtrail:arn` pattern
    (`<management>:trail/*`) and the log-archive bucket's `aws:SourceOrgID` and
    `aws:SourceArn` (`arn:<p>:cloudtrail:*:<management>:trail/*`) statements are
    name-agnostic, so they admit the new trail unchanged. The
    open A1 item (`aws:SourceOrgID` on CloudTrail's KMS calls) applies to it
    exactly as to the old trail.

  Assumed, to prove in the sandbox:
  - The provider's `aws_cloudtrail` creates, reads and updates an organization
    trail from the delegated-admin account. Its docs still say the management
    account; its ID is the trail ARN.
  - The delivery role's trust (`aws:SourceAccount` = management or security
    tooling) is what CloudTrail sends when it assumes a role in the
    delegated-admin account. AWS does not document that case.
  - Importing the existing Organizations registration into
    `aws_cloudtrail_organization_delegated_admin_account` reads cleanly, and the
    management account already has `AWSServiceRoleForCloudTrail` from the old
    trail (the import does not create it, and the event-context role is not
    needed for trails).
  - The security-tooling `tfc-apply` role and its boundary allow `CreateTrail`,
    `PutEventSelectors`, `StartLogging`, `iam:PassRole` of the delivery role and
    `kms:CreateKey`.

  Residuals:
  - aws-organization and aws-security each read
    `aws.enable_cloudtrail_delegated_admin` themselves (not through a
    contract, ADR 0003). Set it in the config file, not as a variable on one
    workspace: a value set on only one root makes them diverge (the plans fail
    closed rather than leave a gap, but the estate is half-migrated until both
    agree).
  - The SCP stops `StopLogging` / `DeleteTrail` on the new trail for everyone
    but break-glass (`DenyDisableSecurityServices`). `UpdateTrail`,
    `PutEventSelectors` and `PutInsightSelectors` are denied to member
    principals except the pipeline roles (`tfc-apply`, which must create the
    trail, `OrganizationAccountAccessRole`, `stacksets-exec-*`) and break-glass
    (`DenyWeakenSecurityServices`), and only from the security accounts
    (`DenyCentralDetectionOutsideSecurityAccounts`). `RemoveTags` and the
    trail resource policy are not in the SCP. What is exempt is detected, not
    prevented: `sec-notify-org-trail-tamper` (security tooling, the trail's
    home Region, the only Region where these calls succeed) alerts on every one
    of those calls on the new trail, to the security-notifications topic.
    Assumed: the organization trail delivers security tooling's own API calls
    to that account's default event bus. With the flag on, `org-guard-alerts`
    (management account) also alerts on any trail change made from the
    management account (phase-0 or break-glass; SCPs never apply there), on
    any trail.
  - The security-tooling CMK now grants `events.amazonaws.com`, scoped by
    `aws:SourceAccount`, so EventBridge can publish `sec-notify-*` alerts to
    the encrypted security-notifications topic. **Validate in the sandbox**
    that EventBridge's KMS calls carry `aws:SourceAccount`. If they don't, the
    grant needs its own statement without that condition.
  - The new trail's log group, CIS alarms, alarm topic and CloudWatch CMK in
    security tooling lack the management role's explicit denies
    (`DenyTrailAndKeyDestruction*`). The CMK's key policy grants the account
    root `kms:*`, so IAM in security tooling governs it. The security-tooling
    `tfc-apply` (StackSet-managed, under the tfc-apply boundary) could delete
    the log group or alarms, or schedule key deletion. That is not denied per
    ARN: an inline deny would need a change to the tfc-oidc-baseline StackSet
    role. Deleting the log group stops CloudWatch delivery only; S3 delivery
    and log-file validation continue.
  - `aws-security` forgets its generic registration with a manual
    `terraform state rm` (runbook step 1.3). A skipped step fails closed: the
    plan shows a destroy and the apply is denied.

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
- **NCC hub/spoke connectivity** (`gcp.network.ncc_hub`, `gcp.network.connectivity`,
  `gcp.environments.<env>.network_connectivity`; `modules/gcp/network/ncc-hub`,
  `modules/gcp/network/ncc-spoke`). Not yet sandbox-proven: run path (a) of
  [the migration runbook](runbooks/gcp-peering-to-ncc-migration.md) on the sandbox
  spoke, then re-plan to 0 changes, before adopting it or making `ncc` the
  scaffolder default. Still to confirm against the real API: the producer spoke
  passes the consumer VPC **name** as `linked_producer_vpc_network.network` (the
  provider example's form); the NCC folder roles (hubAdmin / spokeAdmin /
  hubViewer) are enough to create a cross-project spoke on an auto-accepting
  group; adopting the service-created spoke group by name needs no import, and
  deleting it with the hub succeeds; path (b) route precedence (NCC subnet routes
  over the temporary VPN's dynamic routes).
- **Smaller opt-ins from the 2026-11 remediation, mock-tested only.**
  SCC v2 notification/mute configs (`gcp_overrides.scc_api_version = "v2"`);
  `gcp_overrides.disable_default_sink`; hub IPAM explicit-CIDR allocation
  (`ipam_mode_for_new_vpcs_only`, `ipam_new_vpcs`); the declarative EC2 Allowed
  AMIs policy (`ec2_allowed_images`, `audit_mode` by default, so it only logs);
  the Suspended deny-all and Sandbox guard SCPs (on by default where those OUs
  exist). Apart from those two SCPs, each keeps today's behaviour until set
  (UPGRADING.md); none has run against a real organization yet.
- **Hybrid connectivity (HA VPN, Cloud Interconnect, Site-to-Site VPN)**
  (`gcp.network.vpn`, `gcp.network.interconnect`, `aws.network.vpn`;
  `modules/gcp/stages/net-hub`, `modules/aws/stages/network-hub`). Mock-tested
  only; no on-premises peer was available. Still to confirm: the NCC hybrid
  spoke (`ncc_vpn_spoke`, center group on STAR, default on MESH) accepts the HA
  VPN tunnels and on-premises learns the environment spokes' routes through it;
  on AWS, that on-premises traffic really traverses the Network Firewall in both
  directions (VPN attachment in the `hybrid` TGW table defaulting to inspection;
  routes propagated into the `inspection` table only). On AWS a spoke is
  reachable from on-premises only once it is wired through
  `aws.network.spoke_attachments` (see the spoke-routing entry above).
  - **GCP tunnel secret changes replace the tunnel.** `google_compute_vpn_tunnel`
    has no in-place update for its secret: switching `shared_secret` to
    `shared_secret_wo`, or raising `vpn_shared_secret_wo_version`, is a
    replacement (treat it as ForceNew; confirm in a sandbox plan). That is an
    outage for the tunnel, and with NCC the replacement can be blocked while the
    hybrid spoke still links the old tunnel. Plan rotations as a maintenance
    window: [runbook](runbooks/gcp-hybrid-connectivity.md).
  - **State exposure.** The GCP key is write-only (`vpn_shared_secret_wo`, never
    in state); the legacy `vpn_shared_secret` of `stages/net-hub` is in state
    until v1.0 removes it (UPGRADING.md). The AWS tunnel keys default to
    Secrets Manager (`preshared_key_storage = SecretsManager`; the stage outputs
    `vpn_preshared_key_arn`, not the keys). Setting `Standard` puts the AWS
    keys in state.

- **GCP additional regions in hub and spoke VPCs** (`gcp.network.additional_regions`,
  `gcp.environments.<env>.additional_regions`; `additional_regions` on
  `network/tiered-vpc`, `stages/net-hub`, `stages/net-spoke`). Mock-tested only.
  Each extra region adds one regional subnet per tier to the same global VPC
  and, with `nat` (default true), a Cloud Router and Cloud NAT. The existing
  single-region addresses are unchanged when the map is empty. Still
  single-region (primary region only):
  - Private Service Connect endpoint, HA VPN and its NCC hybrid spoke, the flow
    log export KMS key ring and the `dns-anchor` VPC. Private Service Access and
    VPC-SC are not regional. Interconnect attachments already take a per-entry
    `region`.
  - Workload placement: `stages/environment` still deploys app services
    (Cloud Run, Cloud SQL, GKE Autopilot) and the VM backup policy in the
    primary region. The extra-region subnets exist and can be shared with
    service projects, but no app-services input places a workload there yet.
  - Overlap validation covers subnet primary ranges only, not `secondary_ranges`
    or the PSA range.
  - Under NCC a spoke exports every subnet range; a non-empty
    `ncc.include_export_ranges` on `stages/net-spoke` must list the
    additional-region CIDRs too. AWS multi-region stays at ADR 0009.

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
- **S4 — RESOLVED (2026-11-05).** The Terraform floor is now `>= 1.17, < 2.0` (raised from `~> 1.11`) and secrets use
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

- **S-M3 — RESOLVED (2026-11-07): SaaS bridge values stay out of workload
  state.** `envs/aws/workload` and `envs/gcp/workload` read the Supabase outputs
  with `ephemeral "tfe_outputs" "saas"` (tfe 0.83) and write them with the
  write-only `secret_string_wo` (AWS) / the secret-manager module's ephemeral
  `secret_data_wo` path (GCP). No `terraform_remote_state` or `data "tfe_outputs"`
  read remains: either would store every saas output, secrets included, in the
  workload's state. The write-only version must be non-ephemeral, so it comes
  from `saas.bridge_rotation` in the config file (or `saas_bridge_version`); a
  postcondition on the ephemeral read fails the plan until the saas workspace
  publishes the same `bridge_version`. Unit-tested with `mock_ephemeral`
  (Terraform 1.17). **Residual (sandbox):** `terraform state pull` on a bridging
  workload, showing no secret value, has not been run against a live workspace.
- **SaaS secrets stay in `saas-*` state (provider limitation).**
  `supabase_project` has no write-only `database_password`, so the creation-time
  password is in the `saas-<name>` state and its `supabase_database_password`
  output. The service-role key is in the same state as a data-source result and
  an output. Full state read is limited to organization owners, the team that
  confirms saas applies (`saas_approvers_team_id`, else
  `control_plane_approvers_team_id`), the listed `extra_remote_state_consumers`
  and, only with `enable_saas_state_backup = true`, the state-backup team.
  Viewers and the platform team get `state_versions = none` there. The
  `saas-outputs-reader` teams read outputs only, ephemerally, for the bridging
  workloads. Rotation: see
  [saas-bootstrap](runbooks/saas-bootstrap.md#bridging-secrets-to-a-workload-and-rotating-them).
- **Viewers keep fixed `read` on the platform (tfc-admin) project.** tfc-admin
  state holds no secret by design: sensitive variables are written write-only
  (`value_wo`), and its `data "tfe_outputs"` reads of `gcp-bootstrap` and
  `aws-organization` (stored in its state in full) return only identifiers:
  project IDs and numbers, service-account emails, WIF pool and provider names,
  role names, account and OU IDs, and role and topic ARNs. Neither root marks
  an output sensitive. A future secret output in either root, or a secret
  passed to tfc-admin without `sensitive = true`, would reach viewers.

## OPEN — WS3 trust-model residuals (2026-11-11 due-diligence audit)

- **SaaS bridge push model (SEC-1 follow-up).** Workloads with
  `enable_saas_secret_bridge = true` still hold a `saas-outputs-reader`
  `TFE_TOKEN`. tfc-admin marks them secret-bearing (no platform plan, no
  speculative plan), so only the approvers team and organization owners can run
  code that reads the token. A push model (`saas-<name>` writes the cloud
  secrets) would remove the token from the workloads, but it needs AWS and
  Google credentials in the saas root, which breaks the per-cloud workspace
  split in [provider selection](architecture/provider-selection.md). Revisit
  after the sandbox run.
- **Secrets that tfc-admin does not write are invisible to it.** tfc-admin
  derives secret-bearing workspaces from the variables it writes (sensitive or
  secret-named), from `enable_saas_secret_bridge`, and from the fixed tfc-admin
  and `saas-*` workspaces. A secret that a person adds by hand in the HCP
  Terraform UI on any other workspace, with no bridge flag, is not detected:
  that workspace keeps its normal platform access and speculative plans. The
  same holds for project and organization variable sets that a person creates
  by hand. Set every secret through tfc-admin's write-only
  `workspace_variables`.
- **Who still runs code with a secret-bearing workspace's tokens.** On a
  secret-bearing non-production workload the approvers team now confirms runs,
  so it gains plan-level reach to that workload's bridge `TFE_TOKEN`
  (decision D1). The tfc-admin team, organization owners and anyone who can
  merge to the VCS branch also run code with those tokens.
- **`disable_speculative_on_saas = false` re-enables PR plans on `saas-*`**
  even while `enable_speculative_on_secret_bearing = false`. The `saas-*`
  workspaces keep their own switch.
- **`no_plan_time_code_execution` acts after the plan.** HCP Terraform
  evaluates policy sets after the plan. A `data "external"` / `data "http"`
  block, a provider binary that is not on the allowlist, or a redirected
  provider endpoint has already run with the workspace's credentials when the
  policy fails. For those the policy marks the run and stops its apply; it
  prevents only apply-time effects (provisioners, writes through a redirected
  endpoint). The checks before the plan are `scripts/check-plan-time-exec.py`
  in CI (run by `scripts/check-consistency.sh`) and `runs = read` for the
  platform team on secret-bearing projects. The CI check parses the repo's
  `.tf` and `.tf.json` files and applies the same lists, read from the policy
  files. When branch protection requires `Validation Summary`
  ([BRANCH_PROTECTION.md](guides/BRANCH_PROTECTION.md)), it blocks the merge, so
  no run on the main branch plans the change. It does not stop a
  speculative plan that HCP Terraform starts for the same pull request at the
  same time (off on secret-bearing workspaces unless
  `enable_speculative_on_secret_bearing` is set), and it never sees a CLI
  upload.
- **`removed` blocks are invisible to `no_plan_time_code_execution`.**
  Terraform does not render a `removed` block in the plan JSON (verified with
  Terraform 1.17.1). A destroy-time provisioner in one runs at apply without
  the policy seeing it. What limits it today: `scripts/check-plan-time-exec.py`
  in CI fails on a provisioner in any `removed` block in repo code, and confirming an apply needs
  apply rights (the platform team has `runs = read` on secret-bearing
  projects). A CLI upload by someone with apply rights is not covered.
- **OPA cannot attest module content.** The provisioner allowlist pins the
  module-call chain and its source strings, not the bytes of
  `modules/supabase/vault-secrets` or its `scripts/*.mjs`. The policy does
  not pin the run's workspace either, so any workspace whose root has the
  same two calls and the same relative sources passes. HCP Terraform's policy
  input may carry `run.workspace` fields; pinning the rule to the `saas-*`
  workspaces must first be verified against a real HCP run, because a wrong
  field name would fail closed and block every saas apply. A CLI upload can
  carry a modified copy at the same paths. The saas project's `runs = read` for the platform team and
  approvers-only confirmation are the control there.
- **Endpoint overrides that the plan JSON does not show.** The policy reads
  the argument names in `configuration.provider_config.*.expressions`.
  Terraform does not render a `dynamic` block inside a provider block there
  (verified with Terraform 1.17.1: a `dynamic "endpoints"` block on the `aws`
  provider is absent from the JSON). `scripts/check-plan-time-exec.py` flags
  such a `dynamic` block in repo code before the merge. Environment variables (for example
  `AWS_ENDPOINT_URL_STS`, `HTTPS_PROXY`, `TFE_HOSTNAME`) and an AWS shared
  config file (`endpoint_url`) never appear in the plan. Workspace variables
  that tfc-admin writes go through its reviewed configuration; a variable that
  a person adds by hand in the HCP Terraform UI does not.
- **Credential-file arguments are not checked.** The policy does not look at
  the aws provider's `shared_config_files`, `shared_credentials_files` or
  `profile` (a file can set `credential_process`, which runs a command, or
  `endpoint_url`), or the google provider's `credentials` /
  `external_credentials` (an `external_account` file names its own
  `token_url`). `envs/aws/security` and the other AWS roots legitimately set
  `shared_config_files` to the TFC dynamic-credential file, so a fix needs
  value-based rules, not a deny by argument name.
- **Remote-state `hostname` is not checked.** `terraform_remote_state` must
  use the `cloud` or `remote` backend, but the policy does not check a
  `hostname` in its `config`. When `config` is built from locals or variables
  the plan JSON shows only references, so such a check could not be complete.
  No remote-state read in this repo sets `hostname`.
  `scripts/check-plan-time-exec.py` does not check `config.hostname` either.
- **The supabase `access_token` provider argument is allowed.** The policy and
  `scripts/check-plan-time-exec.py` deny the inline-credential keys
  `credentials` and `token_url` in provider blocks, but not `access_token`:
  `envs/saas` sets the supabase `access_token` to a placeholder when Supabase
  is off. A change to that argument relies on review.
  `impersonate_service_account` is also allowed, because every GCP root sets
  it.
- **The plan-time execution gate trusts the pull request's own copy.** CI runs
  `scripts/check-plan-time-exec.py`, the policy files it reads in
  `policies/opa/` and the parser lock in `.github/requirements/` from the pull
  request's head. One pull request can widen an allowlist (or weaken the
  script) and use the wider list in the same change. The intended control is
  CODEOWNERS review on `/policies/`, `/scripts/check-plan-time-exec.py` and
  `/.github/requirements/`. `.github/CODEOWNERS` gives the security team
  `/policies/`, `/.github/` (which includes `.github/requirements/`),
  `/scripts/check-plan-time-exec.py` and `/scripts/check-consistency.sh`. Other
  files in `/scripts/` have the platform team only. The teams are placeholders
  until a fork sets its own (`scripts/init-landing-zone.sh --codeowners`).
- **What the plan-time execution gate does not scan.** It parses tracked
  `*.tf` and `*.tf.json` files only. `*.tftest.hcl` and `*.tfmock.hcl` files
  are not scanned: `terraform test` runs them in CI with mock providers and in
  the sandbox end-to-end workflow with sandbox credentials, never in an HCP
  Terraform workspace. The code behind a module source pinned to this
  repository's release tag (`git::…?ref=vX.Y.Z`) is not scanned either; it
  was checked when that release was cut.
- **Delegable infrastructure roles (SEC-4 residual).** `compute.admin`,
  `dns.admin`, `container.admin` and `cloudsql.admin` stay delegable. A
  projects-apply compromise can grant itself those on an environment folder.
  None grants data-plane IAM. The roles that control IAM, identities,
  data-plane IAM or project ownership are granted by gcp-organization.
- **organization-apply's paths to a guardrail-owner role (SEC-3 residuals).**
  organization-apply holds `folderCreator`, `folderEditor` and `folderIamAdmin`
  at the org node (no `folderAdmin`, which carries
  `resourcemanager.projects.setIamPolicy` on every project), and a
  role-conditioned `iam.securityAdmin`
  (`modifiedGrantsByRole.hasOnly(organization_apply_grantable_roles)`; the
  gcp-bootstrap validation rejects every role that controls IAM, identities,
  projects or PAM). It can no longer grant itself `denyAdmin`, or a role that
  leads to the guardrails SA, on the org node or the admin project. These paths
  remain:
  - **PAM** (`enable_pam`). organization-apply holds
    `privilegedaccessmanager.admin` and can edit the JIT entitlement's eligible
    principals, approvers and roles. The PAM service agent, not
    organization-apply's `setIamPolicy`, makes the grant. Alert
    `pam_entitlement_change`. Owner: security team (move PAM ownership to
    `gcp-guardrails`).
  - **Principal access boundary** (`enable_principal_access_boundary`).
    organization-apply holds `projectIamAdmin` on the admin project (for the
    policy binding). It can grant itself `serviceAccountTokenCreator` on the
    `<prefix>-guardrails-apply` SA there. Owner: security team (find a role
    with only `resourcemanager.projects.createPolicyBinding`, or apply the
    binding from `gcp-guardrails`).
  - **Alert deletion.** organization-apply holds `monitoring.editor` on the
    admin (audit) project, where the guardrail alerts live. Deleting them no
    longer opens an escalation, so they are defence in depth. Owner: platform
    team.
  - **Folder self-grants.** `folderIamAdmin` at the org node lets
    organization-apply grant itself any role on any folder, for example owner
    of every workload or shared project. That is data plane, not the guardrails:
    the admin project and every automation SA sit directly under the org node.
    Keep the separate logging project (`gcp.logging_project_id`) outside any
    folder, or this path reaches it. Owner: platform team.
  - **Allow-list data roles.** organization-apply can grant itself
    `storage.objectCreator` or `cloudkms.cryptoKeyEncrypterDecrypter` (on its
    default allow-list for the logging project) on any bucket or key that the
    tag-scoped containment rule does not cover. Owner: platform team.
  - **Not validated on a real org.** That IAM accepts the condition on an
    org-node `iam.securityAdmin` binding, that a `setIamPolicy` call with only
    audit-config changes passes it, and that `folderCreator` + `folderEditor` +
    `folderIamAdmin` cover a real gcp-organization apply. Owner: platform team
    (sandbox apply).

## DECISION — needs a human call

- **Behaviour-changing security defaults** (not applied, would change posture):
  packet-mirroring default mirrors all traffic; vpc-peering exports public-IP
  subnet routes; the shared VPC-endpoint policy is `Action="*"`.
- **Toolchain currency automation.** Renovate owns Terraform providers and
  lockfiles (`renovate.json`: weekly `lockFileMaintenance`, one grouped
  `hashicorp/*` PR, labelled for review, never auto-merged, provider majors
  disabled); Dependabot keeps GitHub Actions and the CI Python tooling. The
  Renovate GitHub App still has to be installed by an operator. Open calls:
  `semanticCommits` is off (the `fix(deps):` prefix is set by hand; Dependabot
  also updates the `pg` package of `vault-secrets`), and
  `required_version` / provider-major bumps stay manual by design.

## Scanner coverage

- **Checkov parsing errors.** With checkov 3.3.17, `-d modules` reports 1 parsing
  error and `-d envs` reports 3. The files are `modules/gcp/stages/environment/variables.tf`,
  `envs/gcp/workload/variables.tf` and `envs/aws/network/variables.tf`. They pass
  `terraform fmt`, and CI runs `terraform validate` on every root, so they are
  treated as Checkov parser limits. Checkov does not scan those three files, so a
  misconfiguration in them would not be caught by Checkov. Trivy and CI validation
  still cover them. They do not fail the gate. Re-check after each Checkov upgrade.
