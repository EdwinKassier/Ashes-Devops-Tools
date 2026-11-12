# Changelog

All notable changes to this landing zone are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the repository
follows [Semantic Versioning](https://semver.org/) (pre-1.0: a minor bump may break).

**Versioning.** The repository as a whole is released as `vX.Y.Z` by
[release-please](https://github.com/googleapis/release-please) (`.github/workflows/release.yml`,
`release-please-config.json`): every merge to `main` updates a release PR whose version is
derived from Conventional Commit subjects (`feat:` → minor, `fix:` → patch while pre-1.0).
Merging that PR tags `vX.Y.Z` and publishes the GitHub Release. These repo-version tags are
distinct from the per-workspace **deployment** tags (`gcp-organization/vX.Y.Z`,
`gcp-workload/<env>/vX.Y.Z`, `aws-*/vX.Y.Z`, …) that `terraform-apply.yml` uses to record
release metadata for a Terraform Cloud run.

**How this file is written.** Every user-facing commit adds a line to the Unreleased section by
hand. release-please only tags and bumps versions: `"skip-changelog": true` in
`release-please-config.json` stops it from writing this file.

**Status:** release-please is configured but does not run until a maintainer creates the release
GitHub App and sets `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY`
([CI secrets](docs/guides/CI_SECRETS.md#release_app)). `v0.1.0` was tagged by hand.

---

## [Unreleased]

### Score-8 remediation ([2026-11-06 five-dimension audit](docs/audit/2026-11-06-five-dimension-audit.md))

#### Security

- **Mandatory destroy guard in its own overridable set (T-H4).** `destroy_guard` moves to
  `policies/opa-destructive/` as a mandatory policy that denies every delete or replace of a
  stateful type (GCP, AWS and `supabase_project`). tfc-admin attaches it as
  `<prefix>destructive-change-guard` with `overridable = true`, so the hand-created security team
  (`security_team_id`, granted Manage Policy Overrides by an owner) overrides an intended destroy;
  the guardrails set stays non-overridable. `enable_policy_sets` defaults to on when `vcs_repo` is
  set and the new `org.tfc.plan` is `standard` or `premium`, else a check warns that destructive
  changes are unguarded. `drift-detection.yml` fails a leg whose workspace does not exist instead
  of skipping it, unless `REAL_CLOUD_CHECKS_OPT_OUT=true`. Upgrade steps: `UPGRADING.md`.
- **GitHub WIF tenant pin is an exact match (S-H2).** `custom.wifProviderTenantPinned` no longer
  runs a structural regex over a GitHub provider's condition (a `)` inside a string literal could
  close the "one parenthesised group" early and OR a `true` beside the owner pin). The condition
  must now equal `assertion.repository_owner_id == "<id>"` for an allowed owner ID. app-services,
  gcp-bootstrap and `modules/gcp/iam/workload-identity` render exactly that string
  (`make consistency` asserts it), and pin repository, ref and environment in the principalSet
  bindings through the new mapped attributes `repo_ref`, `repo_env` and `repo_ref_env`. This also
  fixes app-services services that share a repository with different ref/environment pins: each
  deploy SA is now reachable only by its own tuple. **Breaking:** see [UPGRADING.md](UPGRADING.md).

#### Toolchain

- **Terraform 1.17.** Every `versions.tf` requires `>= 1.17, < 2.0`, and CI pins 1.17.1.
  tfc-admin's workspace `terraform_version` default is `~> 1.17`. Compatibility inputs carry
  `deprecated`. Producer `contract` outputs are typed, and `check-contracts.sh` compares their
  type keys with `local.contract`. `check-consistency.sh` guards the version pins and rejects
  `import` blocks in modules. **Breaking:** see [UPGRADING.md](UPGRADING.md).
- **SaaS bridge secrets never reach workload state (S-M3).** The workload roots read the saas
  outputs with `ephemeral "tfe_outputs"`. The write-only version comes from `saas.bridge_rotation`
  (or the new `saas_bridge_version`), and a postcondition fails the plan until the saas workspace
  publishes the same `bridge_version`. Upgrade steps: `UPGRADING.md`.

### Wave A of the [2026-11-06 enterprise boilerplate audit](docs/audit/archive/2026-11-06-enterprise-boilerplate-audit.md)

- **The management aws-security role cannot disable org detection (S-H1).** Disabling delegated
  admins or trusted access and deregistering delegated admins now need the off-by-default
  `enable_security_service_teardown` gate, which is a separate inline policy. The role is
  also denied trail untagging and resource-policy edits, CIS-alarm deletion and disabling,
  and trail log-group, log-stream, metric-filter and retention deletion. `aws-organization` owns the new
  `org-guard-alerts` topic (us-east-1, CMK-encrypted, `aws.guard_alert_emails`). Its EventBridge
  rule covers those calls and org-trail selector and tag changes, with forwarding from every
  other enabled region.

#### Fixed

- **Compliance docs no longer overstate controls (CMP-01, CMP-09, CMP-12).** DET-05 is a
  Scaffold: the incident-response Lambda only logs the finding. SECURITY.md states what the
  `gcp_no_basic_roles_high_scope` policy covers, that Cloud Armor is off by default, and that
  Google APIs are reached through Private Google Access and Private Service Connect, not Private
  Service Access. The HIPAA 164.312(c)(1) row maps to backup and deletion-protection controls.
- **The AWS bootstrap docs match the code (ADO-02, ADO-08).** The operator creates only the
  management account; `aws-organization` creates the organization or imports one through
  `aws.adopt`. That apply also enables trusted access for `sso.amazonaws.com` and registers the
  IAM Identity Center delegated administrator, so the manual gate is now only enabling Identity
  Center in the console. The old runbook told operators to register the delegated administrator
  by hand, which fails after the apply. Known gaps records the unproven order and the missing
  brownfield import.
- **The quick start works as written (ADO-01, ADO-03, ADO-07, ADO-10, ADO-12, ADO-13).** The
  config commit in README.md, QUICK_START.md and the scaffolder is now `chore(config): landing
  zone`, which the commitizen hook accepts. `config/landing-zone.example.yaml` and the scaffold
  fixtures name the phase-0 stack's `OrganizationBreakGlass` role in `aws.break_glass_role_arn`.
  The scaffolder lists both phase-0 role ARNs as values to check against the stack outputs, and
  names the SaaS bootstrap runbook when SaaS is enabled. The GCP bootstrap verification reads the
  `contract` outputs and checks the GitHub pool only with `enable_github_wif`. The README module
  counts per domain now add up to 66 GCP and 53 AWS, and its CI table lists every workflow.
- **Every root's backend now initialises (C1).** All 14 `envs/**/backend.tf`, plus both clone-me
  templates, declared `backend "cloud" {}`. That is not a valid backend type: Terraform rejects
  it, so `terraform init` failed on every root. They are now top-level `cloud {}` blocks.
- **`tfc-admin` is self-managed by default (C3).** `manage_tfc_admin_workspace` now defaults to
  `true`. An unmanaged `tfc-admin` workspace kept TFC's default of speculative plans on, so a PR
  plan could read its org-admin `TFE_TOKEN`. A `check` warns when the workspace is unmanaged and
  VCS-connected.
- **SaaS workspaces no longer run speculative PR plans (S5).** This is the new
  `disable_speculative_on_saas` variable, default `true`. The Supabase and Vercel tokens are
  static and account-wide.
- **Drift detection and E2E no longer show green when they did not run (C4).** An unconfigured
  run now fails. Scheduled runs may skip only with the repository variable
  `REAL_CLOUD_CHECKS_OPT_OUT=true`, and the drift summary never says "no drift" for a run that
  never happened.

#### Added

- `scripts/check-backends.sh` (`make backend-check`, in `make ci`, and in the CI `Terraform Format`
  job). It runs a real, credential-less `terraform init` of every root and template. It passes only
  if init stops at HCP Terraform auth, so an invalid backend fails the PR, not the first apply.
- `make required-checks-live` (`check-required-checks.sh --live`) diffs `BRANCH_PROTECTION.md`
  against the branch protection GitHub actually enforces: contexts, `strict` and `enforce_admins`.
  It needs repo-admin `gh` auth, so it is not part of the PR gate.

#### Security (Wave B)

- **S8 — GitLab WIF trust is no longer a prefix match.** The condition is now
  `namespace_path == X || startsWith(X/)`. Before, `acme` also trusted `acme-evil`.
- **A1 — Root-deny SCP lets centralized root sessions through.** It now carries
  `BoolIfExists aws:AssumedRoot=false`, so the `sts:AssumeRoot` remediation path works.
- **S1 — OIDC persistence backdoors are closed on AWS:**
  - The RCP pins web-identity federation per issuer. TFC tokens are accepted only from your TFC
    organization (`pin_tfc_federation_to_org`, default on). GitHub tokens are accepted only from
    `github_federation_owners` (config `aws.github_federation_owners`).
  - The `tfc-apply` permissions boundary denies `iam:CreateOpenIDConnectProvider`,
    `iam:CreateSAMLProvider`, `iam:UpdateSAMLProvider`, `iam:AddClientIDToOpenIDConnectProvider`
    and `iam:UpdateOpenIDConnectProviderThumbprint`.
  - The account-wide GitHub OIDC provider is now created by the `tfc-oidc-baseline` StackSet
    (`create_github_oidc_provider`, default true).
- **S3 — Detection settings are reachable only from the security accounts.** A new
  `DenyCentralDetectionOutsideSecurityAccounts` deny-tamper statement covers GuardDuty
  filter/detector updates, CloudTrail selector/trail updates and Security Hub standard disabling.
  Outside `central_detection_account_keys` (default `security_tooling`, `log_archive`) these are
  denied to every principal except break-glass, the pipeline included. Config recorders and flow
  logs stay pipeline-managed, because workload baselines own them.
- **A4 — GuardDuty Runtime Monitoring now manages its agents** (Fargate, EKS, EC2;
  `runtime_monitoring_agent_management`). Before, it was billed but produced no findings.
- **S2 — Workload identity federation is restricted on GCP.** The org baseline now enforces
  `iam.workloadIdentityPoolProviders`, which allows only the TFC and GitHub issuers
  (`allowed_workload_identity_issuers`). It also enforces `iam.workloadIdentityPoolAwsAccounts`
  (deny unless listed), `compute.restrictProtocolForwardingCreationForTypes` (INTERNAL),
  `compute.disableVpcExternalIpv6` and `compute.setNewProjectDefaultToZonalDNSOnly`.
- **S4 — GCP admin containment is on by default for production estates.**
  `enable_admin_containment` now defaults to `null`, which means on whenever an environment is
  `is_production`. The break-glass principal comes from the new config key
  `gcp.break_glass_group`. A production estate without one fails the plan
  (`output.admin_containment_enabled` precondition) instead of only warning.
- **D1 — `org_policy_overrides` (stage and root).** Change, drop or add any baseline GCP org
  policy without forking the stage.
- **`gcp.resourceLocations` uses region value groups.** A bare region is now
  `in:<region>-locations`, so zonal resources in that region are allowed.
- **The TFC WIF issuer is parameterised** (`tfc_hostname`, in `workload-identity`, the bootstrap
  stage and both roots). HCP EU and TFE now work on GCP.
- **New config keys:** `gcp.break_glass_group`, `gcp.alert_emails` and `gcp.admin_containment`.
  The bootstrap runbook now lists the Cloud Identity groups as prerequisites.
- **S6 — One management-account role pair per management-default root.** The new module
  `modules/aws/iam/tfc-management-roles` is created by `aws-organization`
  (`enable_tfc_management_roles`, default true). It gives `aws-security` and `aws-backup` their
  own exact-subject plan/apply roles:
  - **`aws-security`:** delegated-admin registration and the organization trail only.
  - **`aws-backup`:** `BACKUP_POLICY` org policies only.
  - **Denied for both:** assuming `OrganizationAccountAccessRole` or member `tfc-*` roles,
    account/OU changes, and editing any `tfc-mgmt-*` role.

  `tfc-admin` binds them from the aws-organization outputs. Only `aws-organization` keeps the
  shared phase-0 role.
- **S7 — Privileged CI secrets are environment-scoped.** The `release`, `docs-bot`, `tfc-drift`
  and `tfc-readonly` jobs run in GitHub environments. CI_SECRETS.md documents moving the secrets
  into those environments, with main/tag-only deployment policies.
- **The RCP data perimeter now covers ECR and CloudWatch Logs** (`ecr:*`, `logs:*`).
- **`organization-policy` gains a `policy_contents` output**, for evidence and tests.

#### Post-re-score fixes (independent re-score at ac707f9)

- **Critical: custom org-policy constraints are now enforced.** The org-policy module created
  `google_org_policy_custom_constraint` but never a `google_org_policy_policy`, so
  `custom.wifProviderTenantPinned` and every `custom_org_constraints` entry were inert. Each
  constraint now gets a policy: `enforcement = enforce` (default), `dry_run` (log only, to stage a
  new constraint) or `off`. The tenant pin uses `wif_tenant_pin_enforcement`.
- **The GitHub WIF pin requires matching quotes** around the owner ID. The `.` wildcard let
  `== "123' && x" == false` through. The RE2 bypass corpus now includes mismatched-quote and
  relation-chaining cases.
- **The aws-security role can no longer quietly defeat audit:**
  - `cloudtrail:UpdateTrail`, `kms:PutKeyPolicy`, `kms:CreateGrant` and `kms:DisableKeyRotation`
    are denied (break-glass only).
  - CloudWatch alarm writes are scoped to the trail's own `<trail>-*` alarms.
  - Create-time `kms:TagResource` is granted, which a tagged `CreateKey` needs.
  - Delegated-admin registration fails closed when no security account is given.
  - `PutEventSelectors` stays allowed, because `aws_cloudtrail` calls it on create. Selector changes
    are caught by the CIS CloudTrail-configuration alarm.
- **Partition: the AWS-managed policy ARN defaults are normalised.** In the tfc-oidc-baseline
  template they become `Fn::Sub arn:${AWS::Partition}:...`. In Identity Center permission sets and
  the backup stage they use the provider partition.
- **AWS Backup delegated admin is the dedicated backup account** (`backup_account_id`), and the
  management role's account pin includes it.
- **The provenance guard also catches `Audit finding X`, `finding #N` and `round-N` comments.**
  The 5 it had missed are stripped.

#### Post-re-score fixes (independent re-score at a6e4edb)

- **The GCP WIF tenant pin rejects the CEL ternary.** `... == 'acme' && true ? true : true` matched
  the previous pattern. The AND-only tail now excludes `?` as well as `|`, and a bypass corpus runs
  through Terraform's RE2 in the stage tests. The earlier "tested against bypass strings" claim
  covered only `||` strings.
- **aws-security management role, third pass:**
  - `logs:*`, `sns:*` and `kms:*` are scoped to the org trail's log group, its `<trail>-*`
    topics, and keys tagged `Workspace = aws-security`. CreateKey requires the tag, so it cannot be
    planted on another key.
  - Delegated-admin registration is pinned to the security-tooling account's ARN.
  - `account.amazonaws.com` is dropped from the service-principal list.
  - The plan-role data-read deny is extended.
- **Partition support is real for the AWS control plane.**
  - Every `^arn:aws:` validation now accepts `aws-us-gov` / `aws-cn`.
  - ARNs built in log-archive-bucket, kms-key, account, iam-role, incident-response,
    route53-resolver, securityhub-org, the security and organization stages and the
    security/network/shared-services/workload roots use the provider's partition.
  - Still to override by hand on GovCloud or China: the AWS-managed policy ARN **defaults**
    (`arn:aws:iam::aws:policy/...` in identity permission sets, tfc-oidc-baseline and the
    organization stage). Variables cannot compute defaults.
- **Break-glass.**
  - The phase-0 stack's `OrganizationBreakGlass` role is now inert by default
    (`BreakGlassActive=false` adds a deny-all inline policy) and is activated with a stack update.
  - The runbook is rewritten for that path, because the dedicated aws-security role can no longer
    manage the role.
  - A check warns on `create_break_glass = true`.
- **The deny-tamper SCP also blocks `s3:PutBucketPolicy` / `DeleteBucketPolicy`** on the log
  archive for non-privileged principals.

#### Final re-score fixes

- **Critical: `aws-security` management role escalation, second pass.** Limiting role writes to
  one role name did not help, because whoever can write a role can make it anything. The role now
  has no IAM role writes at all:
  - aws-organization creates the trail's CloudWatch delivery role
    (`create_org_trail_delivery_role`), and aws-security only passes it to CloudTrail
    (`cloudtrail-org` `cloudwatch_logs_role_arn`).
  - Delegated-admin registration is limited to the security service principals.
  - IAM Identity Center (`sso`) delegation moves to aws-organization
    (`identity_center_admin_account_key`).
  - `cloudtrail:*` is scoped to the organization trail ARN.
  - `cloudwatch:TagResource` is added for the tagged CIS alarms.
- **GCP WIF tenant pin is structural, not a substring check.**
  `custom.wifProviderTenantPinned` now uses anchored RE2 checks. The tenant clause must be the first
  conjunct, with nothing OR-ed beside it, so `org != 'acme'` and `... || true` are rejected.
  app-services renders its GitHub condition in that canonical form.
- **No unpinned GitHub provider.** The baseline creates the account-wide GitHub OIDC provider only
  once `github_federation_owners` / `_owner_ids` is set.

#### Golden paths and test depth

- **Per-service observability and messaging in both app-services golden paths:**
  - **AWS:** per-service CloudWatch alarms (CPU, memory, 5xx, p99 latency, DLQ depth). They notify
    a KMS-encrypted SNS topic, and the workload key policy now lets `cloudwatch.amazonaws.com`
    use the key. An optional SQS queue with a DLQ gives the task role access to its own queue only
    (`services[*].alarms` / `.queue`).
  - **GCP:** per-service alert policies (5xx ratio, p99 latency) with notification channels from
    the root (`app_alert_notification_channel_ids`). An optional Pub/Sub topic and subscription
    with a dead-letter topic gives the runtime SA access to its own topic and subscription only
    (`services[*].alerts` / `.pubsub`).
- **Consistent `tags` / `labels` inputs.**
  - 27 AWS modules gain `tags`, applied to every taggable resource. Resource-specific tags such as
    `Name` still win. The network-hub and workload stages pass it through.
  - 10 GCP modules gain `labels` (validated GCP label syntax), applied to every labelable
    resource, including `resource_labels` / `user_labels`.
  - Modules are now taggable when consumed outside this repo, without provider `default_tags`.
- **Validation and contract suites for every AWS layer root** (backup, identity,
  shared-services, network, security): 10 new suites, about 70 runs.
- **`aws-network` `az_count` minimum is now 2.** One AZ passed validation but could not plan
  (the Route 53 Resolver needs two subnets). The `nonprod-aws-network` preset that used 1 is
  fixed.
- **SaaS root errors name the `saas.stacks` / `saas.defaults` keys.** The hub VPC-SC access policy
  now comes from config (`gcp.network.vpc_sc_access_policy`).

#### First-run fixes from the boilerplate re-score

- **The default `production` profile now plans `aws-security`.** The Security Lake metastore role
  (`AmazonSecurityLakeMetaStoreManagerV2`, with the apply boundary) is created in code when
  `meta_store_manager_role_arn` is empty. It used to be an undocumented, hand-made prerequisite.
- **The AWS phase-0 artefacts are shipped:**
  - [`templates/aws/bootstrap/phase0-management.yaml`](templates/aws/bootstrap/phase0-management.yaml)
    creates the TFC OIDC provider, `tfc-mgmt-plan` / `tfc-mgmt-apply` with exact-subject trust, and
    the MFA-gated `OrganizationBreakGlass` role.
  - [`templates/aws/bootstrap/delete-default-vpcs.yaml`](templates/aws/bootstrap/delete-default-vpcs.yaml)
    is the org-wide default-VPC deletion StackSet.
  - Both pass `cfn-lint` (`make cfn-lint`).

#### Re-audit fixes (independent re-score, 2026-11-06)

- **Critical: the `aws-security` management role could take over the org.** It allowed
  `iam:*Role` on any role in the management account, which sits outside every SCP. It could create
  a role, attach admin to it and pivot.
  - IAM writes are now limited to the trail delivery role (`security_trail_role_pattern`), with
    `iam:PassRole` only to CloudTrail.
  - Trail stop/delete and key destruction are denied.
  - The break-glass role names are protected.
  - Plan roles now carry the data-plane read deny.
- **`aws-backup` no longer needs CloudFormation.** The member Backup service-role StackSet moves
  to aws-organization (`create_backup_service_role`, default on). The aws-backup stage only
  references the role (`create_backup_role_stack_set` restores the old behaviour). Tagging backup
  policies is scoped by policy ARN rather than an unsupported condition key.
- **Federation completeness on AWS:**
  - The RCP denies the built-in web-identity providers (Cognito, Google, Facebook, Amazon) unless
    they are allow-listed (`allowed_builtin_web_identity_providers`).
  - A baseline SCP statement, `DenyIdentityProviderChanges`, denies creating or updating OIDC/SAML
    providers to everyone except break-glass and the StackSet execution role.
  - The GitHub pin accepts immutable `repository_owner_id:<id>:*` subjects
    (`github_federation_owner_ids`).
  - A check warns when the baseline deploys a GitHub provider that is unpinned.
  - `dp:*` tag tampering is now also denied on ECR and CloudWatch Logs, in both the SCP and the
    boundary.
- **GCP WIF tenant pinning.** A custom constraint, `custom.wifProviderTenantPinned`, requires an
  HCP Terraform provider to reference this estate's TFC organization, and a GitHub provider to
  reference an allowed `repository_owner_id` (`pin_wif_to_tfc_organization`,
  `wif_github_owner_ids`).
- **The region-restriction SCP exempts `sts:*`.** ACM and KMS are confined to the allowed regions
  plus us-east-1, so CloudFront edge certificates work.
- **More suppression actions are scoped to the security accounts:** GuardDuty IP sets, Security
  Hub automation rules and control updates, Inspector filters, Access Analyzer archive rules.
  `central_detection_account_keys` is now validated, so a typo can no longer silently drop the
  statement.
- **OPA.** `aws_iam_federated_trust_pinned` now catches partial tenant wildcards
  (`organization:acme*:`). A new advisory policy, `aws_iam_federated_trust_unknown`, reports trusts
  that cannot be checked at plan time.
- **tfc-admin** rejects reserved env vars (`TFC_*`, `TF_CLI_ARGS*`, provider auth) in the
  committed `tfc-workspaces.yaml`.
- **`split_workload_projects`.** AWS workload accounts now trust the `<prefix>aws-workloads`
  project.

#### Wave D

- **Phase-0 human impersonation can be time-boxed.** `phase0_admin_impersonation_expires_at`
  adds a `request.time` IAM condition, through the new `impersonation_expires_at` input on
  `iam/service-account`. A check warns when a production estate keeps an open-ended human path to
  terraform-admin.
- **The PSC Google-APIs endpoint switches to the `vpc-sc` bundle once the environment's perimeter
  is enforced** (`private_service_connect_target`, default derived).
- **The OPA set goes from 8 to 10 mandatory policies.**
  - New `aws_iam_federated_trust_pinned`: web-identity trusts must pin `aud` and a literal-tenant
    `sub`.
  - New `gcp_no_basic_roles_high_scope`: no Owner/Editor at organization or folder scope.
  - `aws_iam_no_admin_wildcard` now also flags `NotAction` on `Resource "*"`.

- **D2 — AWS organization-policy escape hatches**, mirroring GCP's `org_policy_overrides`:
  - `policy_overrides` merges over the built-in set, replacing or adding policies.
  - `disabled_policies` drops built-ins.
  - Both are passed through the stage and root as `org_policy_overrides` /
    `disabled_org_policies` / `org_policy_attachments`.
  - The unattached duplicate `backup-policy` is disabled by default.
- **The org-wide EC2 declarative baseline is attached at the root** (`declarative-ec2-baseline`:
  IMDSv2, no public snapshot/AMI sharing, no serial console). VPC Block Public Access stays
  Workloads-scoped.
- **New `aiservices-opt-out` policy** (`AISERVICES_OPT_OUT_POLICY`, enabled by default). Policy
  types are shape-validated instead of fixed-listed, so new AWS policy types are accepted.
- **TFC run triggers along the dependency DAG** (`enable_run_triggers`, default true). An upstream
  apply queues the downstream plan, direct edges only. Apply order is no longer left to the
  runbooks alone.
- **Audit provenance codes are stripped** from 117 code comments and descriptions.

#### Boilerplate (Wave C)

- **`make` sets a shared `TF_PLUGIN_CACHE_DIR`**, so `make ci` on a fresh clone no longer
  downloads a provider copy per directory.
- **gcp-bootstrap gets the immutable workspace IDs automatically.** tfc-admin writes
  `tfc_workspace_ids` onto the workspace (`set_gcp_bootstrap_workspace_ids`). For the local
  phase-0 run, `output.gcp_bootstrap_tfvars` produces the tfvars line. A production estate requires
  these IDs, and the runbook now says so.
- **`org.profile: starter | production`** for `aws-network` and `aws-security`. Starter drops the
  Network Firewall, Security Lake, Macie, record-all Config and EBS malware scanning. Explicit
  toggles still win.
- **Brownfield AWS adoption.** `adopt_existing` (config `aws.adopt`) imports an existing
  organization, OUs and accounts. A new runbook,
  [`aws-brownfield-adoption.md`](docs/runbooks/aws-brownfield-adoption.md), covers Control Tower
  coexistence. `aws-security` gains `create_organization_trail`, so it does not run a second org
  trail next to Control Tower's.
- **The SaaS path is config-driven.** `saas.stacks.<name>` over `saas.defaults` supplies the
  Supabase org/project/region and the Vercel team/project/repo/branch. tfc-admin sets `stack` on
  each `saas-<name>` workspace. A new runbook covers it:
  [`saas-bootstrap.md`](docs/runbooks/saas-bootstrap.md).

#### Migration

- **Organization.** Set `TF_CLOUD_ORGANIZATION=<org>`, and `TF_CLOUD_HOSTNAME` for HCP EU or TFE,
  instead of `-backend-config` / `backend.hcl` / `TF_CLI_ARGS_init`. A `cloud` block rejects
  `-backend-config`.
- **Per-environment workspaces.** `gcp-workload`, `aws-workload` and `saas` now select their
  workspace by tags (`cloud:<cloud>` + `layer:workload`) and `TF_WORKSPACE=<full workspace name>`,
  instead of a `prefix`. Workspaces created by `envs/tfc-admin` already carry these tags. Tag any
  hand-created workspace to match.
- **GitHub OIDC provider.** `app-services` / `aws-workload` `create_github_oidc_provider` now
  defaults to `false`, and the provider ARN is derived for the account. In an account where
  Terraform already created the provider, either keep `create_github_oidc_provider = true`, or
  `terraform state rm` it and let the StackSet adopt the URL. Set
  `create_github_oidc_provider = false` on `tfc-oidc-baseline` for accounts where the StackSet
  must not create it.
- **First `tfc-admin` apply after upgrading.** It adopts the existing `tfc-admin` workspace through
  the import block, which now sets its VCS triggers and turns speculative plans off. If the
  workspace is deliberately CLI-only, set `manage_tfc_admin_workspace = false`.

Remediation of the [2026-11-05 enterprise boilerplate audit](docs/audit/archive/2026-11-05-enterprise-boilerplate-audit.md).

### Added

- **HCP Terraform audit trail export (CMP-13).** `.github/workflows/tfc-audit-trail.yml` copies
  the audit trail daily to the write-once state-backup buckets under `tfc-audit/`. HCP keeps 14
  days. The export is off until its token secret is set.
- **Patch install target tag.** `patch_install_target_tag` (aws-workload variable,
  `aws_overrides` in aws-security) limits the weekly patch install, and its reboots, to tagged
  instances. Null keeps every SSM-managed instance.
- **gcp-guardrails deployment tags.** The release workflow verifies `gcp-guardrails/v*` tags with
  a guardrails-only read token (`TFC_TOKEN_GUARDRAILS`, tfc-admin
  `guardrails_release_reader_team_id`).
- **AWS account quota pre-flight.** `make aws-preflight` (`scripts/aws-preflight.sh`) checks that
  the Organizations account quota fits the accounts in the config file.
- **Read-only plan targets.** `make plan-gcp-<root>`, `make plan-aws-<root>` and
  `make plan-aws-workload` plan any root in HCP Terraform. Every `apply-gcp-*` and `apply-aws-*`
  target refuses.
- **`make ci-quick`.** Runs the offline gates that need no `terraform init`; `make ci` runs it
  first. `make install` installs `check-jsonschema` at the CI version.
- **Module API check and versioning policy (IAC-3).** `scripts/check-module-api.sh`
  (`make module-api`, meta-lint) fails when a module input, output or directory is removed
  without a breaking-change commit. `docs/policies/versioning-and-compatibility.md` states what a
  version promises.
- **Renovate owns the toolchain (CICD-13, IAC-6).** Renovate updates `.tool-versions`,
  `.terraform-version`, the TFLint plugins, every in-repo tool version and the pre-commit hook
  revs. The weekly `dependency-heartbeat.yml` workflow fails when Renovate has been silent for 8
  days (on a fork it only warns, unless `RENOVATE_HEARTBEAT_REQUIRED=true`).
- **HCP health assessments are the drift source.** With the repository variable
  `TFC_HEALTH_ASSESSMENTS=true`, the drift workflow skips; unset, it runs as the Free-tier
  fallback.
- **Release discipline** — release-please (`release-please-config.json`, `.release-please-manifest.json`,
  `.github/workflows/release.yml`) cuts SemVer `vX.Y.Z` releases from Conventional Commits; baseline `0.1.0`.
- **Docs drift gates** — `scripts/check-docs-counts.sh` (`make count` / `make count-check`) recomputes the
  module, root and test-suite counts and fails CI (meta-lint) when README.md / CLAUDE.md disagree;
  `scripts/check-md-links.py` (`make links`) fails on broken repo-relative Markdown links.
- **TFLint AWS ruleset** — `tflint-ruleset-aws` 0.50.0 alongside the google ruleset, covering the AWS modules.
- **ShellCheck** — pinned `shellcheck-py` pre-commit hook and `make shellcheck` for `scripts/*.sh`.
- Commit the `examples/presets/*.tfvars` production/cost presets, with a CI guard that every referenced preset exists.
- `envs/gcp/workload` `default_plan` test that plans the real host stage with no module override.
- **Required-check guard** — `scripts/check-required-checks.sh` (`make required-checks`, CI meta-lint)
  fails if `docs/guides/BRANCH_PROTECTION.md`'s `gh api` command lists a context no workflow job reports
  (sharded matrix or reusable-workflow caller names).
- **Backtick-path strict mode** in `scripts/check-md-links.py`: repo paths (`modules/`, `envs/`,
  `policies/`) named in code spans must exist — fatal for `docs/compliance/control-matrix.md`, advisory
  for `docs/known-gaps.md`.
- `scripts/check-module-usage.py` (`make count`, informational) lists modules no root reaches;
  README labels them *(library-only)*.
- Script tests: `scripts/tests/test-init-landing-zone.sh` (`make test-scripts`, CI meta-lint) runs the
  config scaffolder non-interactively and asserts yamllint-clean output and the substituted values.
- Root templates (`templates/aws/root`, `templates/shared/cloud-root`) now carry the root conventions:
  `config.tf`, a contract-gated remote-state read and a `tests/` suite. `templates/**` suites run in CI.
- `scripts/check-consistency.sh` reports (does not fail on) single-platform `.terraform.lock.hcl` files.
- **Minimum AWS footprint: `aws.layers`.** The config key (tfc-admin variable `aws_layers`) lists
  the optional AWS layer workspaces: `network`, `identity`, `shared-services`, `backup`. Absent =
  all four, so an existing estate keeps every workspace. `aws.layers: []` gives only `aws-organization`
  and `aws-security`. tfc-admin drops every grant, trigger and variable of a dropped layer, and
  sets `enable_network_hub = false` on `aws-workload-<env>` without `network`. `aws-organization`
  binds OIDC trust only for accounts and workspaces that exist. See
  `docs/architecture/provider-selection.md`.

### Security

- **CI hardening (CICD-12, CICD-16, CICD-18).** zizmor scans every workflow (`make zizmor`,
  meta-lint), template injection and broad drift permissions are removed, and every job that holds
  a secret or an OIDC token blocks egress except to its listed endpoints
  (`scripts/check-github-governance.sh` enforces it).
- **Plan-time execution policy is exact and covers Lambda, actions and inline credentials (SEC-2, breaking).**
  `no_plan_time_code_execution` allows a provisioner only in `module.saas_workload.module.vault_secrets`
  with the exact source strings of `envs/saas`; a source that only ends in `supabase/vault-secrets` is
  denied. `external`, `http` and `aws_lambda_invocation` data sources are denied everywhere, and so is every
  `action` block whose type is not on the new, empty `allowed_action_types`. A provider allowlist covers
  every provider the repo declares. Provider endpoint, proxy and TLS overrides and the provider keys
  `credentials` and `token_url` are denied, and `terraform_remote_state` must use the `cloud` or `remote`
  backend. Forks extend `policies/opa/no_plan_time_code_execution_allowlist.rego`. HCP Terraform runs the
  policy after the plan, so it stops the apply and detects, but does not prevent, plan-time execution. See
  `UPGRADING.md`.
- **The plan-time execution gate parses HCL (SEC-2 / CICD-2, breaking).**
  `scripts/check-plan-time-exec.py` replaces the grep in `scripts/check-consistency.sh`. It parses every
  `.tf` (python-hcl2, hash-locked in `.github/requirements/hcl2.txt`, `regex` pinned to 2026.9.29) and
  `.tf.json` file, so bare labels, qualified and version-only provider sources, `check`-scoped data,
  `removed` provisioners, `dynamic` endpoint blocks, endpoint overrides, remote-state backends and
  non-local module sources are caught before the merge. It reads its lists from the OPA policy files and
  fails when the policy's provisioner chain and the code differ. It has no fallback parse: a file that
  python-hcl2 cannot parse fails (`envs/aws/workload/main.tf` now ends lines with `?` and `:`), as do
  `.tf.json` files with duplicate keys, a tracked symlink, a submodule and a path under `.terraform/` or
  `node_modules/`. Files come from `git ls-files`, the policy lists must be plain string literals defined
  once, and module sources must match exactly. See `UPGRADING.md`.
- **The committed workspace file cannot set redirection env vars (breaking).** tfc-admin rejects
  `TFE_*`, `TF_TOKEN_*`, `TF_CLI_CONFIG_FILE`, the proxy variables in any case, `SSL_CERT_FILE`
  and `SSL_CERT_DIR` in `workspace_variables_file`. See `UPGRADING.md`.
- **saas state is not readable by viewers or the backup team, and saas applies can have their own
  approvers (SEC-7, breaking).** HCP Terraform's fixed `read` includes the full state file, and
  `saas-*` state holds the Supabase database password and service-role key. On the saas project,
  viewers and the platform team now get custom access with `state_versions = none` (the platform
  team loses read-outputs, which can still return a sensitive output), and the state-backup team gets no
  grant unless `enable_saas_state_backup = true`. The new `saas_approvers_team_id` confirms saas
  applies instead of the control-plane approvers; a `check` warns while it is unset. See
  `UPGRADING.md`.
- **projects-apply cannot delegate data-plane IAM roles (SEC-4, breaking).** A folder IAM condition
  limits the roles a delegate grants, not the members, so projects-apply could grant itself
  `secretmanager.admin` on a production folder. `iam.serviceAccountUser`, `secretmanager.admin`,
  `cloudkms.admin`, `storage.admin`, `run.admin`, `bigquery.admin`, `pubsub.admin`,
  `artifactregistry.admin` and `resourcemanager.projectCreator` join the non-delegable workload folder
  roles: gcp-organization grants them to the workload SAs directly. `make consistency` checks that the
  list is the same in gcp-bootstrap, gcp-organization and gcp-projects. See `UPGRADING.md`.
- **organization-apply cannot reach a guardrail-owner role (SEC-3, breaking).** organization-apply
  held an unconditional org `iam.securityAdmin` (it could grant itself `roles/iam.denyAdmin`) and
  `folderAdmin`, whose `resourcemanager.projects.setIamPolicy` reached the admin project and the
  guardrails SA. It now holds `folderCreator` + `folderEditor` + `folderIamAdmin`, and its
  `iam.securityAdmin` carries `modifiedGrantsByRole.hasOnly(<organization_apply_grantable_roles>)`
  (default: billing admin and log-writer roles; IAM-controlling roles are rejected). gcp-bootstrap
  now grants the standing `organizationAdmin` of the org admin groups. gcp-organization checks its
  grants and its org admins against the gcp-bootstrap contract at plan time, and fails when that
  contract is older than this release. See `UPGRADING.md`.
- **GCP app-deploy WIF is never repository-wide (SEC-5, breaking).** A service with `github` but
  neither `ref` nor `environment` bound its deploy SA on `attribute.repository_id`, so every
  branch, tag and environment of the repository could deploy, also in production. It is now bound
  on `attribute.repo_env/<repository_id>/<var.environment>`, as AWS app-services does. The deploy
  job must declare `environment: <env>`, or the entry sets `ref`. See `UPGRADING.md`.
- **Management plan role denies data-plane reads; security/backup are not trusted by the admin role
  by default (SEC-6, breaking).** The phase-0 `tfc-mgmt-plan` role was plain `ReadOnlyAccess`. It
  now has the same data-read deny as the member-account `tfc-plan` role, and
  `scripts/tests/test-phase0-template.sh` keeps the two lists equal. `TrustSecurityAndBackup`
  defaults to `"false"`, so a new stack lets only `aws-organization` apply as management admin.
  See `UPGRADING.md`.
- **tfc-apply boundary closes brownfield escalation (SEC-9) and protected-key alias retargeting
  (SEC-12, breaking).** Boundary propagation covered new roles only. A pre-existing unbounded role,
  group or user stayed reachable. The embedded `tfc-apply-boundary` now denies
  `iam:UpdateAssumeRolePolicy` on every role (`enable_apply_trust_update_lock`, default on; IAM does
  not evaluate `iam:PermissionsBoundary` for that action), new versions of customer-managed
  policies outside `/tfc-managed/`, IAM group and user policies, group membership and console
  password changes. The boundary and the deny-tamper SCP deny `kms:UpdateAlias` and
  `kms:DeleteAlias` on keys tagged `protected = true`, except for break-glass. See `UPGRADING.md`.
- **The drift token's team is codified (SEC-11).** The new tfc-admin input `drift_team_id` grants
  the `TFC_TOKEN_DRIFT` team `runs = plan`, state read and no variable access on every project
  except guardrails and the secret-bearing projects (tfc-admin, `saas-*`, a project with a static
  secret). A refresh-only plan still runs with the workspace's variables, so those workspaces rely
  on HCP health assessments alone (on tiers that offer them). The new output `drift_workspaces` lists what the token can check. The
  token is still made by hand with an expiry, so it never enters state.
- **`npm ci` in vault-secrets runs with a cleared environment (SEC-12, breaking).** The bootstrap and
  reconcile commands run npm under `env -i`. npm gets back only `PATH`, `HOME`, `TMPDIR`, the
  npm cache variables, the proxy variables and `NODE_EXTRA_CA_CERTS`, each one only when it is
  set. `POSTGRES_URL`, `VAULT_DESIRED_JSON`, `SUPABASE_SSL_CERT` and the workspace's
  `SUPABASE_ACCESS_TOKEN` reach `node` only, never npm, its config files or its registry. The
  trigger hashes do not include the command, so no provisioner re-runs on upgrade. A registry or
  auth setting that an estate passed to npm as an environment variable (for example
  `npm_config_registry`) must move to an `.npmrc` file. See `UPGRADING.md`.
- **Secret-bearing workspaces are derived, not listed (SEC-1, breaking).** tfc-admin marks every
  workspace that holds a sensitive or secret-named variable or runs the SaaS bridge, including
  non-production workloads. There the platform team drops to `runs = read`, the workspace runs no
  speculative plans (`enable_speculative_on_secret_bearing` opts back in) and the approvers team
  confirms runs. A `check` warns when a secret-bearing workload shares a project with the control
  plane. See `UPGRADING.md`.
- **destroy_guard covers backup vaults, locks, Object Lock, BigQuery, registries, EFS and DNS zones
  (CICD-11, breaking).** A delete or replace of `aws_backup_vault`,
  `aws_backup_vault_lock_configuration`, `aws_s3_bucket_object_lock_configuration`,
  `aws_efs_file_system`, `google_bigquery_dataset`, `aws_ecr_repository`,
  `google_artifact_registry_repository`, `aws_route53_zone` or `google_dns_managed_zone` now stops
  the run until the security team overrides it. See `UPGRADING.md`.
- **Mandatory OPA controls fail closed on unknown values (CICD-10, breaking).** `gcs_no_public_buckets`,
  `aws_s3_public_access` (the four public access block switches), `aws_kms_key_rotation` and
  `database_private_encrypted` (`storage_encrypted`, `publicly_accessible`) now deny a value that is
  unknown at plan time, through the new `lib.unknown_or_not`. Before, an apply-time value passed
  unchecked. See `UPGRADING.md`.
- **Wildcard WIF bindings are denied (SEC-10, breaking).** The new mandatory OPA policy
  `gcp_wif_principalset_pinned` denies a workload identity principalSet on the whole pool (`/*`),
  `attribute.repository_owner_id`, `attribute.repository` or `attribute.ref`, in any
  `google_*_iam_member`, `_iam_binding` or `_iam_policy`. The GitHub provider condition pins only
  the owner, so each of these trusted every repository of the owner. The advisory
  `gcp_wif_principalset_repo_wide` reports `attribute.repository_id`-only members and members that
  are unknown at plan time. See `UPGRADING.md`.
- **An enforced environment perimeter admits its own pipeline (ARC-13).** gcp-projects adds
  `automation_identities` (the environment's own `wl-<env>-plan` and `wl-<env>-apply` SAs from the
  gcp-bootstrap contract) to each `environment_config` entry. gcp-workload passes them to the
  environment stage (new input `automation_identities`), which adds one ingress rule: those
  identities, any source, every resource in the perimeter, the restricted services only (enforced
  plus staged dry-run). Existing perimeters show an in-place update that adds the rule after
  gcp-projects is re-applied.
- **Production VPC-SC in dry-run fails the plan (SEC-8, breaking).** gcp-workload replaces the
  `vpc_sc_enforced_in_prod` warning with `terraform_data.production_vpc_sc_enforced`, whose
  precondition fails an `is_production` environment whose perimeter is absent or in dry-run. The
  new `production_vpc_sc_dry_run_waiver = { reason, expires }` lets a first rollout plan until its
  `expires` date (UTC). After that date the plan fails again. See `UPGRADING.md`.

### Changed

- **Cloud Run probes and a warm instance in production (breaking, ARC-16).** `modules/gcp/compute/cloud-run`
  takes `health_check_path` and adds an HTTP startup and liveness probe. The app-services stage
  defaults it to `/` (empty string = keep the TCP probe) and keeps one instance warm for every
  production service whose `min_instances` is unset. The key is accepted in every `services` key list
  and in `config/landing-zone.schema.json`. See `UPGRADING.md`.
- **TLS 1.2 minimum on GCP public ingress and Google APIs (breaking, CMP-5).** Each
  `public_ingress` load balancer gets a `MODERN` SSL policy with a TLS 1.2 minimum
  (`app-ingress` inputs `min_tls_version`, `ssl_policy_profile`; a passed `ssl_policy_id` wins), so
  TLS 1.0/1.1-only clients can no longer connect. The production profile sets the org policy
  `gcp.restrictTLSVersion` (denies `TLS_VERSION_1`, `TLS_VERSION_1_1`); opt out with
  `gcp_overrides.restrict_tls_versions = false`. See `UPGRADING.md`.
- **TLS 1.2 minimum on the cdn and internal-lb modules (breaking, CMP-5).** `modules/gcp/network/cdn`
  and the L7 HTTPS path of `modules/gcp/network/internal-lb` create a `MODERN` SSL policy with a
  TLS 1.2 minimum and set it on the HTTPS proxy (inputs `ssl_policy_id`, `min_tls_version`,
  `ssl_policy_profile`, as in `app-ingress`). TLS 1.0/1.1-only clients can no longer connect.
  See `UPGRADING.md`.
- **Hardened audit store for regulated GCP estates (CMP-4).** A `gcp.environments` entry with
  `compliance_class: regulated` fails the `gcp-organization` plan until `gcp.logging_project_id`,
  `gcp.logging_project_number` (not the admin project) and `gcp.enable_audit_bucket_lock: true` are
  set, or `gcp.audit_store_waived: true`. The three keys are new in the config file. The production
  profile warns when an `is_production` environment exists without them, and the plan warns when the
  logging project sits in a folder. See `UPGRADING.md`.
- **Opt-in regulated environment class (CMP-7).** `compliance_class: regulated` on a
  `gcp.environments` entry applies the new `regulated-gcp-workload` preset to that
  `gcp-workload-<env>` (enforced VPC-SC, Cloud Armor with OWASP rules, full flow-log sampling,
  365-day flow-log retention) and fails the plan on a dry-run perimeter, the production waiver or
  weaker flow-log variables. On an `aws.workload_environments` entry it forces the `aws-network`
  Network Firewall and egress gate on every profile and refuses the alert-only waiver.
  `aws.network.vpc_endpoint_policy_mode` adds `aws:ResourceOrgID` to the hub endpoint policy
  (PREVIEW, off by default). See `docs/architecture/regulated-environments.md`.
- **Regulated floors for Cloud Armor and AWS flow-log retention.** A regulated `gcp-workload-<env>`
  fails the plan on `enable_cloud_armor = false` or `enable_owasp_rules = false`. Any regulated
  `aws.workload_environments` entry makes `aws-security` fail the plan when the log-archive
  retention, which holds the VPC flow logs, is below 365 days.
- **Cloud SQL backups stay in region; Backup and DR vault (breaking, CMP-8).** `backup_location =
  null` now means the instance region, not Cloud SQL's nearest multi-region, so new backups stay
  inside `gcp.allowed_regions`. The new `modules/gcp/backup/backup-vault` creates a Backup and DR
  vault (enforced retention, organization-only access) with a daily plan for the app-service
  databases. It is on for `compliance_class: regulated` and opt-in elsewhere
  (`gcp.environments.<env>.backup_vault`); the retention lock is never set by default. The
  workload folder roles gain `roles/backupdr.admin` (non-delegable) and `roles/backupdr.viewer`.
  PREVIEW. See `UPGRADING.md`.
- **SaaS residency check and third-party register (breaking, CMP-11).** `envs/saas` fails the plan
  when the Supabase region, or the AWS region behind the Vercel function region, is outside the new
  `saas.allowed_regions` (else `aws.allowed_regions`). An unknown Vercel code fails closed. The
  Vercel region lists follow Vercel's published table: `arn1`, `hkg1`, `syd1` and `yul1` are added
  and `sea1` is removed. New `docs/compliance/third-parties.md` (DPA, BAA, subprocessors, exit plan
  per provider) and matrix row DP-09. See `UPGRADING.md`.
- **HSM option for audit keys; CMEK for regulated Cloud SQL (CMP-12).** `gcp.audit_key_protection_level`
  (`SOFTWARE` default, or `HSM`) sets the protection level of the two audit CMEK keys; it is
  ForceNew, so a change on existing keys fails the plan. A `compliance_class: regulated`
  `gcp-workload-<env>` fails the plan for an app-service database without `encryption_key_name` or
  without deletion protection (`require_cmek` in `cloud-sql`, `require_database_cmek` in
  app-services). An existing database is never replaced to add a key. See `UPGRADING.md`.
- **Required tags and data classification on both clouds (breaking, CMP-10, ARC-17).** The OPA
  `require_labels` policy is mandatory (not overridable) and checks four keys: GCP
  `managed-by`, `environment`, `cost-center` and `owner` (Cloud SQL from `settings.user_labels`),
  AWS `ManagedBy`, `Environment`, `CostCenter` and `Owner` (in `tags` or `tags_all`). `org.cost_center` and
  `org.owner` feed the GCP default labels and the AWS default tags. Every AWS root adds a
  `DataClassification` default tag: `confidential` in aws-security, `restricted` in aws-backup,
  `internal` in the other layer roots, and `aws.workload_environments.<env>.data_classification`
  in each workload. gcp-projects binds the GCP data-classification tag value to each host project
  (projects-apply gets `tagUser`). The AWS tag policy is built with `jsonencode` and reports the
  four keys as required for the resource types in `aws.tagging.required_for`. Resources get
  in-place label and tag updates. See `UPGRADING.md`.
- **Developer is refused in production accounts (breaking, CMP-14).** aws-identity fails the plan
  when an assignment gives a set in `production_restricted_permission_sets` (default `Developer`,
  which is `PowerUserAccess`) in a production workload account. See `UPGRADING.md`.
- **Hub network alarms (breaking).** The AWS network hub alarms on transit gateway
  `PacketDropCountBlackhole`, NAT gateway `ErrorPortAllocation` (one alarm per gateway) and, with
  the VPN, `TunnelState`. The alarms publish to an SNS topic in the network account, with the
  `notifications.emails` subscribers, or to `alarm_sns_topic_arn`. A production aws-network plan
  fails without a subscriber or a supplied topic. See `UPGRADING.md`.
- **CloudTrail ordering follows data flow (IAC-10).** The CloudTrail modules in aws-security take
  their bucket name from the log-archive bucket policy, not from a module `depends_on`, so data
  sources in the stage stay known at plan time. No plan change.
- **No placeholder SecOps subscriber (breaking, CMP-6).** `aws-security` no longer subscribes
  `secops@example.com`. A production plan (`org.profile = production` or a production AWS workload
  environment) fails until `notifications.emails` or `aws_overrides.notification_subscribers` names
  a real address; example, `.invalid`, `.localhost` and `.test` domains are rejected. Non-production warns.
  See `UPGRADING.md`.
- **Patch Manager installs patches (breaking, CMP-3).** `modules/aws/ops/systems-manager` adds a
  daily `AWS-RunPatchBaseline` Scan association and a weekly Install association (`RebootIfNeeded`,
  Sunday 03:00 UTC, 10% concurrency, never at apply time) on every SSM-managed instance, and one
  baseline per OS in `patch_operating_systems` (default Amazon Linux 2023; `patch_operating_system`
  is deprecated). Opt out with `enable_patch_install = false` (aws-workload) or
  `aws_overrides.enable_patch_install = false` (aws-security). See `UPGRADING.md`.
- **ECS services autoscale in production by default (breaking, ARC-16).** `enable_autoscaling` is
  now unset by default and resolves to `true` when `is_production` is true (new input of the AWS
  app-services stage and of `envs/aws/workload`, read from the config file, never from the
  environment name). See `UPGRADING.md`.
- **One production rule: `is_production` (breaking).** Every `gcp.environments` and
  `aws.workload_environments` entry, and every entry of tfc-admin's `environments` variable, must
  set `is_production`; `config/landing-zone.schema.json` and the roots that read the flag fail
  the plan without it. The names `prod` and `production`, and the `prod` substring match in
  gcp-workload, no longer decide production. `scripts/check-production-rule.sh` (run by
  `make consistency`) fails on any name-based production check. See `UPGRADING.md`.
- **CI performance** — the per-root validate matrix (218 legs, near GitHub's 256-leg cap) is now 10
  round-robin shards; validate, lint and test share a provider plugin cache (`actions/cache`, keyed on all
  `.terraform.lock.hcl` files) and TFLint caches its ruleset plugins. `Validation Summary` remains the
  single fail-closed required check.
- **tfsec removed** (end-of-life, folded into Trivy): `make security` and pre-commit now run
  `trivy config` (CRITICAL/HIGH, same as the CI gate); Trivy pinned to 0.70.0 in `.tool-versions` and in
  `reusable-security.yml`.
- Checkov pinned to the CI version (3.3.17); `make security` refuses a skewed local binary.
- `make apply-gcp-organization` / `make apply-gcp-workload` now refuse and point to Terraform Cloud —
  local apply contradicted the documented apply rules.
- README, CLAUDE.md, docs/INDEX.md, Quick Start and Add Environment updated for the five-root GCP flow
  (`gcp-bootstrap` → `gcp-organization` → `gcp-projects` → `gcp-network-hub` → `gcp-workload-<env>`).

### Deprecated

- **Deletion-protection inputs use `enable_*deletion_protection` (IAC-8).** Ten inputs are renamed:
  `deletion_protection` and `delete_protection` become `enable_deletion_protection`,
  `alb_enable_deletion_protection` becomes `enable_alb_deletion_protection` and
  `app_alb_enable_deletion_protection` becomes `enable_app_alb_deletion_protection`. The old
  names stay as deprecated aliases until v1.0; when both are set, the new name wins. No plan or
  state change. See `UPGRADING.md`.
- `modules/gcp/stages/host` — the network god-module facade (no in-repo callers) is **removed in
  `v1.0.0`**. Migrate to `stages/net-hub`, `stages/dns-anchor` and `stages/net-spoke`; see the module
  README for the per-use mapping and reference `moved.tf` files.

- **The real config file is schema-validated (IAC-2).** `make config-check` and the pre-commit hook
  validate a fork's committed `config/landing-zone.yaml` against `config/landing-zone.schema.json`, and a
  consistency check fails when a root reads a `local.lz` key that the schema lacks. An unknown key fails
  CI. Keys that no root reads yet are marked as reserved in the schema. See `UPGRADING.md`.
- **Locked central backup copy, DR copy and restore testing (CMP-1, breaking, opt-in).** With
  `compliance.backup.copy_to_central_vault`, aws-backup creates `org-backup-copy-vault` in the backup
  account: a customer managed key, a Compliance-mode Vault Lock and a vault policy that admits copies from
  the organization only. aws-organization creates customer-managed-key member vaults, and
  `compliance.backup.dr_region` adds a copy in a second region. Restore testing covers EBS, EC2, RDS,
  Aurora, S3, DynamoDB and EFS and moves to the copy vault. The vaults send notifications for failed backup,
  copy and restore jobs, and the `tfc-apply` boundary denies the pipeline deleting the copy vault, its lock
  or its policy. The default does not change (decision D3); a production scaffold turns the copy on. Two
  changes break existing users: `rds-aurora` tags every cluster `backup = true` (opt out per service with
  `database.enable_org_backup = false`), and the Compliance lock becomes irreversible after
  `changeable_for_days`. See `UPGRADING.md`.
- **Audit and log retention come from config, with framework floors (CMP-2).**
  `compliance.audit_log_retention_days` feeds the GCP audit bucket (`gcp-organization`) and the AWS log
  archive (`aws-security`, with a configurable Object Lock mode). The plan fails when the value is below the
  floor of a listed `compliance.frameworks` entry (pci_dss 365, hipaa 2190, fedramp_moderate 913), or
  below 365 days while the GCP audit bucket lock is on. On AWS it also fails when frameworks are set and
  the lock mode is `GOVERNANCE`. Unset keys keep 365 days and the plan does not change. See
  `UPGRADING.md`.

### Fixed

- **tfc-admin fails the plan when an upstream contract lacks the credential keys (IAC-9).** The
  reads of the gcp-bootstrap and aws-organization outputs have a postcondition that names each
  missing `TFC_*` dynamic-credential key. Before, a renamed or missing output dropped those
  variables from every workspace silently.
- **The internal DNS domain comes from config.** `gcp.network.internal_domain` (variable
  `internal_domain` in gcp-network-hub) sets the internal root zone. The default stays
  `internal.local`, so no plan changes. A later change replaces the zone. See `UPGRADING.md`.
- **AWS validations accept GovCloud and the European Sovereign Cloud.** ARN checks accept the
  `aws-eusc` partition next to `aws`, `aws-cn` and `aws-us-gov`, and region checks use
  `^([a-z]{2}|us-gov|eusc-[a-z]{2})-[a-z]+-[1-9][0-9]?$` in the modules, roots, scaffolder and
  config schema. The commercial form is unchanged. The partitions are not tested against a live
  account.
- **`compliance.breach_notification_contacts` is read (behaviour change).** The key was reserved
  and read by no root. aws-security now adds one email subscriber each (`notify-dpo-<i>`) to the
  security-notifications topic, and the production placeholder guard rejects a placeholder
  breach contact. gcp-organization adds the addresses to the control-plane alert channels, each
  address once. An explicit `aws_overrides.notification_subscribers` or
  `gcp_overrides.alert_notification_emails` still replaces the config list.
- **aws-backup checks `dr_region` at plan.** The effective `dr_region` (variable, else
  `compliance.backup.dr_region`) must be in `aws.allowed_regions` (else `["eu-west-2"]`, as in
  aws-organization) and differ from the home region. Before, a region the region SCP denies passed
  the plan, and the cross-region copy failed at run time.
- **The GCP Private Service Connect endpoint for Google APIs can now be created (ARC-1).**
  `net-hub` and `net-spoke` named it `<network>-psc` (for example `hub-vpc-core-psc`). Google
  allows only 1-20 lower-case letters and numbers, starting with a letter, so the first hub and
  environment network apply failed. The name is now the network name without non-alphanumerics
  (first 17 characters) plus `psc` (for example `hubvpccorepsc`). The global address also needs
  an explicit IP: it defaults to the second-to-last address of the VPC block (for example
  `10.0.255.254`), and the plan fails when it is inside a subnet range of the VPC (in the hub,
  also the Secure Web Proxy proxy-only and PSC NAT subnets when the proxy is on). The Secure Web
  Proxy examples now use `10.0.250.0/23` and `10.0.252.0/24`, which do not hold that address. New config
  keys `gcp.network.private_service_connect` and `gcp.environments.<env>.private_service_connect`
  (`name`, `address`) override both. The `private-service-connect` module now requires `address`
  and validates `name`. The old name and an address-less reservation could never be created by
  the API, so no existing state holds them and no migration is needed.
- **The AWS root template writes the required tags and accepts every partition's regions.**
  `templates/aws/root` sets provider `default_tags` (`ManagedBy`, `Environment`, `CostCenter`,
  `Owner` from `org.cost_center` and `org.owner`, `DataClassification`) and validates `aws_region`
  with the canonical region regex, which `scripts/check-consistency.sh` now checks in `templates/`.
- **Key allowlists of untyped inputs live in one place and are checked against the stage types
  (IAC-4).** The `type = any` inputs keep a misspelled key visible, and a validation rejects keys
  outside an allowlist. Each allowlist now lives in the owner's `allowed_keys.tf` (gcp-workload,
  gcp-network-hub, aws-network and `modules/gcp/stages/environment`), and
  `scripts/check-any-allowlists.py` (`make consistency`) fails when a list differs from the
  attributes of the stage object it is forwarded to (`scripts/any-allowlists.json`), or when a
  new `type = any` input has no allowlist. Every existing list matched its stage type. gcp-network-hub
  `vpn`, `interconnects` and `hub_additional_regions` had no allowlist: a misspelled key in the
  variable or in `gcp.network.vpn`, `interconnect` or `additional_regions` was dropped silently.
  The plan now fails and names the key.
- **Organization policies are checked against the real AWS size quotas (ARC-18).** The tests
  held the RCP to 10,240 characters, but AWS caps an RCP at 5,120 (an SCP at 10,240).
  `modules/aws/governance/organization-policy` now fails the plan when a rendered policy is over
  its type's quota (SCP 10,240, RCP 5,120, AI services opt-out 2,500, other types 10,000), so long
  role names, many trusted accounts or an override fail at plan, not at apply. New tests render
  every policy with long names and with every option that adds statements, and the
  aws-organization stage tests that no target carries more than 5 RCPs, `RCPFullAWSAccess`
  included. The worst case measures 6,485 characters for `scp-deny-tamper` and 2,811 for
  `rcp-data-perimeter`, so no policy is split and no plan changes.
- **The IP plan states capacity and a GKE secondary range plan (ARC-4).** `docs/architecture/cidr-plan.md`
  now lists how many GCP environments and AWS workloads each range holds and how to grow it. It
  proposes `100.64.0.0/10` for GKE Pods and Services, says which parts Google's documentation
  confirms and which it does not, and `docs/known-gaps.md` records that the ranges are not provisioned.
- **A regional IPAM pool can grow, and its share can be limited to OUs (ARC-4).** One `/12` pool holds
  14 workloads in the default plan. `aws.network.regional_additional_cidrs` (region => CIDRs) provisions
  extra CIDRs into a region's pool without touching existing allocations. A static hub VPC inside an
  extra CIDR is reserved there, and tfc-admin accepts a workload `vpc_cidr` inside any pool CIDR of the
  home region and fails on an extra CIDR outside `top_cidr` or overlapping another pool CIDR.
  `aws.network.ipam_share_ou_keys` shares the pools with the named OUs instead of the whole
  organization. Both are opt-in: unset keeps one CIDR per region and the org-wide share. The org share
  moves from `aws_ram_principal_association.org` to `.org[0]` (a `moved` block, no change to AWS).
  `docs/runbooks/aws-cidr-expansion.md` has the steps; `UPGRADING.md` has the OU warning.
- **GCP hub peering: one spoke name, a quota guard and an INACTIVE warning (ARC-5).** `gcp-projects`
  publishes `environment_config.<env>.spoke_network_name`; `gcp-workload-<env>` names its VPC with it
  and `gcp-network-hub` peers with it, so the name is derived in one place (a contract without the key
  falls back to `<prefix>-<env>-vpc`). The network-hub stage fails the plan when the environment
  peerings exceed `hub_peering_limit` (default 24: the `PEERINGS_PER_NETWORK` quota is 25 by default
  and Private Service Access holds one). A `hub_peering_active` check in `gcp-workload-<env>` warns
  while the spoke side is `INACTIVE`. The second `gcp-network-hub` run stays manual and is now step 5
  of `docs/runbooks/add-environment.md`.
- **GCP hybrid: the environments are announced on-premises, and DNS works both ways (ARC-12,
  breaking).** DEFAULT BGP mode announced only the hub subnets, never the peered environments. With
  the VPN or an Interconnect and no `advertised_ip_ranges`, the hub routers now use CUSTOM mode: every
  hub subnet (`ALL_SUBNETS`, what DEFAULT announced), every environment CIDR, and `35.199.192.0/19`
  when forward zones exist. The VPN takes a new `advertised_groups` (`network/vpn`, `net-hub`). An
  inbound DNS server policy on the hub VPC (`gcp.network.hybrid_dns.enable_inbound_forwarding`,
  default on) lets on-premises resolvers query the internal zone, and
  `gcp.network.hybrid_dns.forward_zones` forwards on-premises domains from the hub (private path,
  new `forwarding_path` in `network/dns`). A forward zone that equals or sits under the internal
  domain fails the plan. `UPGRADING.md` says what on-premises sees;
  `docs/runbooks/gcp-hybrid-connectivity.md` has the steps.
- **Spoke VPCs get the CIDR their subnets use (ARC-1, breaking).** An IPAM-backed VPC now
  requests `cidr_block` explicitly from the pool by default (`ipam_allocation = "explicit_cidr"`
  in `modules/aws/network/vpc`, `ipam_explicit_cidr = true` in aws-workload). Before, it asked
  for any `/16` while its subnets were cut from `vpc_cidr`, so subnet creation could fail with
  `InvalidSubnet.Range`. `ignore_changes = [ipv4_netmask_length]` keeps existing VPCs in place,
  and a `check` warns when the allocated block differs from `cidr_block`. See `UPGRADING.md`.
- **The static hub VPC ranges are reserved in the IPAM pool (ARC-1, breaking).** The inspection and
  egress VPCs are not IPAM allocations, so the regional pool could allocate their range to a spoke.
  `modules/aws/stages/network-hub` now adds one `aws_vpc_ipam_pool_cidr_allocation` per static hub VPC
  inside the home-region pool (new output `hub_static_ipam_allocations`). A hub VPC that only partly
  overlaps the pool fails the plan. Check that no spoke holds a hub range before you apply aws-network;
  see `UPGRADING.md`.
- **tfc-admin fails on shared or out-of-pool AWS workload CIDRs (ARC-1, ARC-4, breaking).** With
  explicit IPAM allocation, two workloads on the same range collide in the pool, and a range outside
  the home-region pool fails at apply. tfc-admin now counts a workload without `vpc_cidr` as the
  built-in `10.72.0.0/16`, reports overlaps among workloads, and reports a fixed AWS range outside
  `aws.network.regional_cidrs.<org.regions.aws>`. Give every workload its own `vpc_cidr`; see
  `UPGRADING.md`.
- **Spoke DNS peering resolves the internal root zone (ARC-2, breaking).** Each workload peering
  zone (`internal-peering`) targets the hub VPC, but the `internal-root` zone was bound only to the
  DNS anchor VPC, so every internal lookup from a spoke returned NXDOMAIN. `gcp-network-hub` now
  also binds the zone to the hub VPC (an in-place zone update). `gcp-projects` grants each workload
  apply SA `roles/dns.peer` on the shared folder, which creating a peering zone that targets the
  hub VPC needs, and gcp-bootstrap adds `roles/dns.peer` to `delegated_network_folder_roles`. Apply
  in order; see `UPGRADING.md`.
- **The projects-apply delegated folder IAM grant fits the IAM 10-role limit.** IAM accepts at most
  10 roles in one `modifiedGrantsByRole` `hasOnly()` list, but each folder got one condition with
  its whole allow-list (36 workload roles, 13 network roles by default), so the gcp-organization
  apply failed. gcp-organization now binds one condition per 10 roles on each folder (chunk 0 keeps
  the old address, title and description, so a list of 10 roles or fewer plans no change), and the
  legacy org-level binding in gcp-bootstrap does the same. gcp-projects turns off google provider
  batching, which would merge the folder IAM changes on one folder into a single request that spans
  two conditions. See `UPGRADING.md`.
- **AWS roots resolve availability zones from AZ IDs or the region (ARC-3, breaking).** aws-network
  defaulted to `eu-west-2a`/`eu-west-2b`, and aws-workload had no zone input, so any other region
  failed at apply. Both roots now take `availability_zones`, else `availability_zone_ids`, else
  `aws.workload_environments.<env>.availability_zone_ids` (aws-workload), else
  `aws.network.availability_zone_ids`, else the region's first three available zones. AZ IDs map to
  zone names in each account, so spokes can land in the hub's physical zones. aws-workload gains
  `az_count`. An eu-west-2 estate on the defaults plans no change. The roots now read
  `data.aws_availability_zones` at plan. See `UPGRADING.md`.
- **Route 53 Resolver endpoints are opt-in, and the profile is valid (ARC-6, ARC-21, breaking).**
  The resolver module listed the egress VPC as a Route 53 Profile resource, which the API
  rejects, and its endpoints used a placeholder security group, so the first real `aws-network`
  apply failed. The endpoints (about USD 365 per month) are now created only with
  `enable_resolver_endpoints` (aws-network: `aws.network.resolver_endpoints.enabled`, else on only
  with the VPN), with a module-owned security group that admits DNS from `allowed_cidrs` and sends
  DNS only to the forward targets. The profile now carries the DNS Firewall rule group, the
  forward rules and `profile_hosted_zone_arns`. `forward_rules` need the endpoints. New outputs
  `inbound_endpoint_ips` / `resolver_inbound_endpoint_ips`. See `UPGRADING.md`.
- **The central interface endpoints serve the spokes (ARC-6, breaking).** The endpoints in the
  egress VPC had no security group, so the deny-all default group blocked every caller, and their
  private DNS was visible only in the egress VPC. `vpc-endpoints` gains `allowed_cidrs` (a
  module-owned group that admits HTTPS) and `enable_shared_private_dns` (one private hosted zone
  per service with an alias record, output `shared_dns_zone_arns`). aws-network admits `top_cidr`
  and adds the zones to the Route 53 Profile. Spoke traffic to the endpoints stays inspected
  (`docs/known-gaps.md`). See `UPGRADING.md`.
- **Spoke VPCs associate the org Route 53 Profile (ARC-6, behaviour change).** `aws-workload-<env>` now creates an
  `aws_route53profiles_association` for its spoke VPC in the workload account, from the network
  contract `resolver_profile_id` (remote state, `network_contract` or
  `aws.contracts.network.resolver_profile_id`). The spoke inherits the DNS Firewall, the resolver
  forward rules and the central interface endpoint zones. Standalone spokes and a network state
  without the key associate nothing.
- **Prod and nonprod spokes cannot reach each other (ARC-11, breaking).** Both segment tables default-route
  to the same inspection (or, on starter, egress) attachment, whose table knows every spoke, so a
  prod↔nonprod flow was routable and only the firewall policy (pass in alert-only mode) stopped it.
  Each segment table now blackholes the other segment's spoke CIDRs (`spoke_attachments.<key>.cidr`,
  default `aws.workload_environments.<key>.vpc_cidr`; new stage output
  `segment_isolation_routes`). Cross-segment flows that worked before now drop at the TGW. A
  `check` warns when both segments are attached and a spoke has no CIDR. See `UPGRADING.md`.
- **The egress VPC routes on-premises prefixes to the VPN.** The egress VPC private route tables
  sent only `top_cidr` to the transit gateway, and the `shared` TGW table had no on-premises route,
  so Resolver endpoint replies and forwards to on-premises went to NAT. With the VPN on, each
  `vpn.onprem_cidrs` prefix now routes from the egress private tier to the TGW and from the `shared`
  table to inspection, and the egress attachment propagates into the `inspection` table, so both
  directions cross the firewall. A `check` warns when the VPN and the endpoints are on and
  `onprem_cidrs` is empty. With the VPN on, an `onprem_cidrs` prefix that overlaps `top_cidr`, the
  hub VPCs or a spoke `cidr` fails the aws-network plan, and tfc-admin reports it against every AWS
  and GCP range in the config file. The aws-network `vpn` variable no longer fails its key check
  when it sets `onprem_cidrs`. See `UPGRADING.md`.
- **Starter spokes get NAT egress; starter rejects the VPN (ARC-10, breaking).** Without the
  Network Firewall (the `starter` profile) the inspection VPC forwards nothing, so aws-network
  rejected `spoke_attachments` and spokes had no egress. The `prod` and `nonprod` default routes now
  go to the egress attachment when the firewall is off, and each spoke propagates into the `shared`
  table, so starter spokes reach the internet through NAT. This egress is not inspected. With the
  firewall on, nothing changes. A starter estate with `aws.network.vpn.enabled: true` now fails the
  plan (`terraform_data.hybrid_needs_inspection`): on-premises traffic goes to the inspection VPC,
  which forwarded nothing. See `UPGRADING.md`.
- **AZs from another region fail at plan (ARC-3).** `modules/aws/network/vpc` now fails the plan
  when an availability zone name does not start with `region`. Before, the default
  `eu-west-2a`/`eu-west-2b` zones reached every subnet in another region and the apply failed with
  `InvalidParameterValue`. New output `availability_zones` lists the zones the subnets use.
- `docs/guides/BRANCH_PROTECTION.md` listed `Terraform Tests` (a sharded matrix that only reports
  `Terraform Tests (shard N)`) as a required context, which would block every PR. `Validation Summary` is
  now the only required context.
- Restored green CI gates on `main`: `terraform fmt`, TFLint standard module structure (host split
  outputs/variables merged), Checkov 3.3.17 failures (justified skips).
- `gcp-workload`: VPC-SC gated on an access policy being supplied; flow-logs BigQuery destination derived;
  null-safe `for_each` in `vpc-sc` (three default-path plan failures).
- Example workspace name and example-subdomain email guard, with tests.

## [0.1.0] - 2026-11-05

Baseline version for release-please (no tag was cut; the next release PR is computed from
commit `4e05c90`). Summarises the work merged between 2026-09-09 and 2026-11-05 (PR #587).

### Added

- **Application platform core** — runtime, data and secret modules, plus a golden path to deploy a service
  ([deploying-a-service](docs/guides/deploying-a-service.md)) (audit C1).
- **Delivery pipelines** for ECS/Fargate and GKE Autopilot (audit C1).
- `app-ingress` front-door module and an SLO module for application observability (audit C1).
- **Terraform Cloud workspace layer codified** — `envs/tfc-admin` and `modules/tfc/workspace` (audit C3).
- Data-driven service-team registry and promotion model ([promotion runbook](docs/runbooks/promotion.md)) (audit H10).
- **Control-plane self-observability** — `modules/gcp/monitoring/control-plane` (audit M-obs).
- AWS security: manage the break-glass role, not just alarm on it (audit M3).
- **SaaS integration (audit H9, option C)** — opt-in Supabase→GCP and Supabase→AWS secret bridges, a
  frontend-URL seam via `cross_cloud_references`, and `dns-records` modules for Cloud DNS and Route 53.
- CODEOWNERS team-ownership scaffold (removes the bus factor of one).
- Audit remediation batches B (modular production hardening, H1/M2) and C (contain the GCP automation
  identity, C2); FinOps cost toggles, wider drift default, release provenance, CIDR plan.
- Root contract tests (M5), structural assertions (M6) and audit-log wiring tests (M7).

### Changed

- **GCP roots split** — `gcp-bootstrap`, `gcp-projects` and `gcp-network-hub` now have their own roots and
  state alongside `gcp-organization` and `gcp-workload-<env>` (audit H3); WIF trusts the new workspaces.
- `host` god-module decomposed by concern (audit H3).
- google / google-beta pinned `~> 7.0`.
- GitHub Actions bumped (actions group, 8 updates).

### Fixed

- Audit remediation batch A (correctness, WIF and account guards) and batch E (operability, CI accuracy).
- `environments` map validated across the GCP roots (audit H4).
- L2 placeholder-email guard, M-iac contract binding; new [apply-recovery runbook](docs/runbooks/apply-recovery.md).
- Platform modules pass the security and consistency gates; PR gates repaired (stale 6.x locks, long YAML lines).
- Three verified findings from the 2026-11-04 audit; regenerated module READMEs and Markdown list numbering.

## Pre-0.1.0 history (2026-07 to 2026-09-09)

> **Path note:** entries below were written across the domain-driven reorg (see the first
> "Changed" item). Module/root paths in this section reflect the **current** post-reorg
> layout (`modules/<cloud>/…`, `envs/<cloud>/<layer>`); a few older entries name the former
> flat paths (`modules/<category>/…`, `envs/<cloud>-<layer>`) as a historical record.

### Changed

- **Domain-driven repository reorganization** — modules, deployable roots, and scaffolds are now grouped by owning cloud. `modules/` → `modules/{gcp,aws,supabase,vercel,saas}/` (GCP-native modules and stages under `gcp/`, AWS stages under `aws/stages/`, `saas-workload` under `saas/stages/`); `envs/<cloud>-<layer>` → `envs/<cloud>/<layer>` (e.g. `envs/gcp-organization` → `envs/gcp/organization`); `templates/` → `templates/{aws,shared}/`. Relative module `source` paths were rewritten throughout, `scripts/terraform-roots.sh` discovery depth updated, and CODEOWNERS regrouped by cloud. **No Terraform state migration** — TFC workspace names, `backend.tf`, and `terraform_remote_state` (workspace-name) lookups are unchanged; the only operator action is repointing each workspace's VCS working directory, per [`docs/runbooks/ddd-reorg-migration.md`](docs/runbooks/ddd-reorg-migration.md). Delivered as three sequential PRs (modules → envs → templates).

### Added

- **AWS Security Reference Architecture landing zone** — multi-account organization (SRA OU tree + foundational accounts); SCP/RCP/declarative/tag/backup guardrails; org CloudTrail, Config, GuardDuty, Security Hub, Access Analyzer, Macie, Inspector, Detective, and Security Lake; Systems Manager; incident-response/forensics; a Transit Gateway hub network; IAM Identity Center; org Backup with Vault Lock; and cost governance — across 46 `modules/aws/*` modules (including `modules/aws/stages/*`), and 7 `envs/aws/*` roots (`organization`, `security`, `network`, `identity`, `shared-services`, `backup`, `workload`) plus the `envs/saas` root. Provider pinned `aws >= 6.46.0, < 7.0.0`. See [`docs/architecture/aws-landing-zone.md`](docs/architecture/aws-landing-zone.md).
- **Any-combination provider selection** — aws/gcp/supabase/vercel are now independently selectable (one cloud = one root = one workspace). New `envs/saas` root deploys Supabase and/or Vercel with no AWS/GCP credentials; `enable_supabase` added to `modules/saas/stages/saas-workload`. See [`docs/architecture/provider-selection.md`](docs/architecture/provider-selection.md).
- `modules/supabase/project` — creates a single Supabase project via `supabase_project`; lifecycle guard ignores database_password after initial creation
- `modules/supabase/settings` — manages auth and API settings for an existing project via `supabase_settings`; destruction is a no-op by provider design
- `modules/supabase/environment` — composite module (project + settings + `data.supabase_apikeys`); primary building block for per-environment deployments; `anon_key` output is intentionally non-sensitive to allow for-expression filter conditions in callers
- `modules/supabase/vault-secrets` — bootstraps the Supabase Vault with SECURITY DEFINER helpers and reconciles a desired-state `map(string)` of secrets; Node.js >= 18 + `pg ^8.20.0` runtime dependency; IaC namespace limited to UPPER_SNAKE_CASE names; safety guard refuses to wipe a non-empty vault when desired set is empty
- `modules/vercel/project` — creates a Vercel project with QA/preview, UAT/custom, and production environments; drift-resistant sensitive env var handling via `terraform_data` SHA256 triggers; `ignore_command` uses POSIX sh (not bash); `root_directory = ""` converted to `null` to satisfy Vercel API
- `modules/stages/saas-workload` — stage module composing the three child modules above; Vercel and vault-secrets are feature-flagged (`enable_vercel`, `enable_vault_secrets`) to support phased deployment
- `modules/stages/bootstrap/variables.tf` — `project_prefix` validation: must start with lowercase letter, contain only lowercase letters/digits/hyphens, max 10 characters; prevents project IDs exceeding GCP's 30-character limit
- `modules/stages/bootstrap/variables.tf` — `org_id` validation: digits-only, without `organizations/` prefix (matches pattern already enforced in other modules)
- `modules/governance/scc/variables.tf` — `org_id` (digits-only) and `project_id` (GCP 6–30 character format) format validation blocks
- `modules/host/main.tf` — `terraform_data.subnet_cidr_count_guard` precondition: fires when an explicitly-provided CIDR list is shorter than the number of availability zones, surfacing the root cause immediately instead of an opaque `Invalid index` error
- `modules/network/cloud-armor/variables.tf` — CEL `expr` match type added to `custom_rules.match_conditions` alongside the existing `versioned_expr` path; allows header/path/geographic rules without switching to separate OWASP resources
- `modules/network/cloud-armor/variables.tf` — mutual-exclusion validation: exactly one of `versioned_expr` or `expr` must be set per rule; providing both or neither fails at plan time with a clear error
- `modules/host/variables.tf` — `cloud_armor_custom_rules.match_conditions` type updated to match the child `cloud_armor` module: `versioned_expr`, `config`, and `expr` are now `optional`; CEL `expr` rules are now passable through the host module boundary
- `modules/stages/workload/tests/iam_validation.tftest.hcl` — `rejects_billing_creator` test (previously only `billing.admin` was tested despite both being in the deny list)
- `modules/stages/bootstrap/main.tf` — `google_billing_account_iam_member` grants `roles/billing.costsManager` to the Terraform admin SA; without this, `google_billing_budget` creation fails at apply time with a permissions error even when folder-level roles are present
- `modules/governance/org-policy/variables.tf` — duplicate constraint validation on both `boolean_policies` and `list_policies`; prevents silent last-wins overwrite when the same constraint appears twice
- `modules/gcp/governance/org-policy/tests/variables_validation.tftest.hcl` — 2 new tests rejecting duplicate boolean and list policy constraints
- `modules/network/vpc-sc/variables.tf` — `enable_deletion_protection` variable (default `true`); protects service perimeters from accidental destruction via sentinel pattern
- `modules/network/vpc-sc/main.tf` — `terraform_data.deletion_protection` sentinel resource with `prevent_destroy = true`; guards both regular and bridge perimeters when enabled
- `modules/stages/bootstrap/variables.tf` — cross-variable validation: `tfc_organization` must be non-null when `enable_tfc_oidc = true` (previously silent no-op)
- `modules/stages/bootstrap/tests/variables_validation.tftest.hcl` — new test: `rejects_tfc_oidc_enabled_without_tfc_organization`
- `modules/governance/billing/variables.tf` — `functions_bucket` and `function_source_object` validation: both must be non-empty when `enable_email_notifications = true`
- `modules/governance/billing/tests/variables_validation.tftest.hcl` — 4 new tests covering all `enable_email_notifications` cross-variable guards
- `modules/host/variables.tf` — `explicit_zones` now validated with GCP zone name format regex; description updated with ⚠️ production requirement warning
- `Makefile` — `clean-locks` target added (separate from `clean`) with interactive confirmation before deleting committed lock files; `clean` now explicitly preserves `.terraform.lock.hcl`
- `modules/network/vpn/examples/basic/variables.tf` — `vpn_shared_secret` variable (sensitive = true) with instructions for `TF_VAR_` injection; replaces hardcoded plaintext literal
- `modules/governance/cloud-audit-logs/variables.tf` — `sink_name` variable; allows calling module twice in same project without name collision
- `modules/governance/cloud-audit-logs/main.tf` — `google_organization_iam_audit_config` resource: enforces DATA_READ/DATA_WRITE/ADMIN_READ logging org-wide (not just on the admin project)
- `modules/stages/organization/outputs.tf` — new outputs: `audit_logs_bucket_name`, `billing_export_dataset_id`, `scc_pubsub_topic_id`, `cmek_key_names`; removed duplicate `tags` alias
- `envs/organization/outputs.tf` — new outputs: `tag_keys`, `audit_logs_bucket_name`, `billing_export_dataset_id`, `scc_pubsub_topic_id`
- `modules/stages/workload/variables.tf` — `enable_gke_network_user` flag (defaults false); GKE robot SA subnet binding is now conditional instead of always-applied
- `modules/monitoring/alert-policy/variables.tf` — `uptime_check_resource_type` variable (`uptime_url` / `uptime_tcp`); `webhook_notification_channel_ids` output marked sensitive
- `modules/cloud-storage/variables.tf` — `labels` variable; `retention_days` per-bucket field in `data_buckets` object type
- `modules/governance/billing/variables.tf` — `vpc_connector` variable for org-policy compliance; `labels` variable (replaces deprecated `tags`)
- `modules/monitoring/alert-policy` — new module: Cloud Monitoring alert policies and notification channels (CPU, memory, Cloud Run 5xx error rate, P99 latency, uptime, log-based); email + webhook (Slack/PagerDuty) notification channels; 22 mock_provider validation tests
- `modules/host/variables.tf` — `enable_log4j_protection` variable (previously declared in cloud_armor but silently ignored by the host module call)
- `envs/organization/variables.tf` — `terraform_admin_email` variable for SA impersonation; `audit_log_retention_days` variable (configurable retention with compliance guidance for PCI-DSS/HIPAA/FedRAMP)
- `modules/stages/organization/variables.tf` — `audit_log_retention_days` variable with validation
- `modules/stages/workload/tests/iam_validation.tftest.hcl` — 5 new tests rejecting org/folder-level privileged roles (organizationAdmin, folderAdmin, securityAdmin, organizationRoleAdmin, billing.admin)
- `SECURITY.md` — vulnerability disclosure policy and security architecture overview
- `CHANGELOG.md` — this file
- `docs/guides/BRANCH_PROTECTION.md` — recommended branch protection settings
- Input validation on `bootstrap/variables.tf`: billing_account format, github_org/repo format, admin_email, tfc_workspaces conditional guard when `enable_tfc_oidc = true`
- CEL injection guards on `workload_identity/variables.tf`: format validation on `github_organization`, `github_sa_bindings[*].repository`, `gitlab_namespace`, and `tfc_organization`
- Input validation on `host/variables.tf`: project_id format, project_prefix format, region format
- Input validation on `governance/kms/variables.tf`: project_id and keyring_name format
- Conditional validation on `network/vpc-sc/variables.tf`: `access_policy_name` required when `create_access_policy = false`; `protected_projects` must be numeric
- IAM member prefix validation on `cloud_storage/variables.tf` `allowed_members`
- HTTPS URL validation on `governance/billing/variables.tf` `webhook_endpoint`
- Examples for all 33+ modules (complete `modules/*/examples/basic/` coverage)
- `modules/network/shared-vpc-service` — new module for Shared VPC service project attachment
- `modules/stages/workload` — subnet IAM binding output (`subnet_iam_bindings`)
- `modules/stages/bootstrap` — OIDC pool ID outputs (`github_oidc_pool_id`, `tfc_oidc_pool_id`)
- `.terraform.lock.hcl` committed for all example directories (reproducible provider installs)
- `scripts/terraform-roots.sh` — discovers example directories for validate-all and test targets
- `make test` — 400+ test assertions across 41 test suites, all using `mock_provider`

### Changed

- `modules/stages/workload/variables.tf` — `project_admin_roles` description corrected: module uses additive `google_project_iam_member` (not authoritative `google_project_iam_binding`); description now accurately documents the non-eviction behaviour
- `modules/cloud-storage/variables.tf` — `kms_key_name` is now optional (`default = null`); GMEK (Google-managed encryption) is accepted when the variable is omitted; validation is null-safe; description adds upgrade guidance for compliance environments
- `modules/network/cloud-armor/main.tf` — `enforce_on_key_configs` block wrapped in a `dynamic` block conditioned on `enforce_on_key == null`; the Cloud Armor API rejects requests that include both the scalar `enforce_on_key` and the structured `enforce_on_key_configs` in the same rule
- `modules/network/cloud-armor/main.tf` — `match` block now handles both `versioned_expr` + `config` (IP matching) and `expr` (CEL) paths via `dynamic` blocks; both are mutually exclusive at the API layer
- `modules/stages/organization/main.tf` — `module "tags"` call updated to the new `map(object({values, description}))` type with descriptive strings for `environment`, `business-unit`, and `data-classification` keys
- `SECURITY.md` — corrected KMS rotation period documentation from `1–90 days` to `1–365 days` (validation upper bound was relaxed in a prior round)
- `envs/organization/variables.tf` — `github_org` and `github_repo` no longer have personal account defaults; removed to prevent accidentally trusting wrong org when forking
- `modules/host/variables.tf` — `vpn_shared_secret` default changed from `""` to `null` to force explicit configuration
- `templates/module/versions.tf` — constraint updated to `~> 1.9` (consistent with all modules)
- `terraform-apply.yml` — `permissions: contents: write` scoped to `release` job only; `verify-run` job uses `contents: read`
- All GitHub Actions SHA-pinned (removed mutable `@master`, `@v2` references)
- `documentation.yml` — replaced direct `git push` to main with `peter-evans/create-pull-request` PR flow
- Checkov global skip list replaced with per-resource inline suppressions
- `envs/organization/moved.tf` — added cleanup instructions (safe to delete after first migration apply)

### Fixed

- `modules/governance/billing/main.tf` — replaced `google_cloud_run_service_iam_member` (Cloud Run v1 IAM API) with `google_cloud_run_v2_service_iam_member` (Cloud Run v2 IAM API); Cloud Functions gen2 deploys as a Cloud Run v2 service, not v1 — the v1 resource cannot find the service and silently fails to set the invoker binding, preventing Pub/Sub from calling the budget notifier
- **CRITICAL** `modules/stages/network-hub/main.tf:70` — VPC-SC `protected_projects` passed project ID strings instead of required project NUMBERS; the ACM API silently rejects or misinterprets IDs causing misleading permission errors. Renamed `spoke_project_ids` → `spoke_project_numbers` and updated callers to use `module.projects.project_numbers`
- **CRITICAL** `modules/stages/network-hub/main.tf` — `vpc_service_controls` map was always populated unconditionally; when `vpc_sc_access_policy_name = null` the vpc-sc module's validation fires immediately (`access_policy_name must be set when create_access_policy = false`), making VPC-SC opt-out impossible without triggering a plan error. Wrapped in `var.vpc_sc_access_policy_name != null ? { ... } : {}`
- `modules/host/variables.tf` + `main.tf` — `vpc_service_controls` object type was missing `enable_deletion_protection` field; users could not disable the perimeter sentinel through the host module interface, requiring `terraform state rm` workaround. Added `enable_deletion_protection = optional(bool, true)` and wired it through
- `modules/stages/organization/main.tf` — `google_bigquery_dataset.billing_export` had no `lifecycle { prevent_destroy = true }`; BigQuery datasets with tables are destroyed by `terraform destroy` without error, unlike GCS buckets
- `envs/apps/main.tf` — `module "budget"` call omitted `kms_key_name` (app-env Pub/Sub topics unencrypted vs CMEK-encrypted org topics); added comment documenting intentional omission with upgrade path
- `.github/workflows/terraform-plan.yml` — `terraform-docs` install now downloads and verifies SHA-256 checksum before extracting binary; previously any compromised release would execute silently in CI
- `scripts/setup.sh` — `install_tfsec_versioned()` now downloads `tfsec_checksums.txt` and verifies SHA-256 before installing; exits with error if verification fails
- `.pre-commit-config.yaml` — `terraform_checkov` hook now passes `--config-file=__GIT_WORKING_DIR__/.checkov.yaml`; without it local pre-commit runs diverge from CI, causing false-positive commit failures
- `.github/workflows/documentation.yml` — reviewer changed from hardcoded personal username to `${{ vars.DOCS_REVIEWER }}`; configure the `DOCS_REVIEWER` repository variable to set the reviewer
- `scripts/terraform-roots.sh` — `collect_modules` maxdepth raised from 3 to 4; future depth-4 modules would be silently excluded from validate/lint/docs CI steps
- `.github/workflows/reusable-security.yml` — tfsec `config_file` changed from `.tfsec.yml` (resolved relative to `working_directory`, silently missing) to `${{ github.workspace }}/.tfsec.yml` (absolute path, always resolves correctly); all exclusion rules were previously silently ignored for both modules and envs scans
- `.github/workflows/security-scan.yml` — concurrency group now uses `'scheduled'` key for `schedule` events; `cancel-in-progress` is `false` for scheduled runs so a push never cancels a running nightly SARIF scan
- `.github/workflows/documentation.yml` — checkout and create-pull-request now use `DOCS_BOT_PAT` (falls back to `GITHUB_TOKEN`); PRs from `GITHUB_TOKEN` do not trigger downstream CI; added `reviewers` field so auto-generated PRs require approval before merge
- `.github/dependabot.yml` — added `modules/monitoring/alert-policy` and `modules/monitoring/alert-policy/examples/basic` (previously missing; provider updates went untracked)
- `Makefile` — `make security` and `make security-report` now pass `--config-file .checkov.yaml` to both Checkov invocations, matching CI behaviour; previously local runs produced different results than CI
- `Makefile` — `make clean` no longer deletes committed `.terraform.lock.hcl` files (was deleting all lock files outside `envs/`); separated into a guarded `make clean-locks` target
- `.tflint.hcl` — Google plugin remains pinned at `0.39.0` (the latest published release; `0.40.0` does not exist upstream — a prior entry in this file incorrectly claimed a bump to it)
- `envs/apps/variables.tf` — `monthly_budget_limit` description updated to explicitly state that `0` disables budget alerts; added `>= 0` validation with clear error message
- `modules/governance/kms/variables.tf` — rotation period upper bound relaxed from `7776000s` (90 days) to `31536000s` (365 days) to allow annual rotation for HSM-backed keys; comment documents NIST SP 800-57 recommendation for software keys
- `.github/workflows/terraform-apply.yml` — added `--max-time 30 --connect-timeout 10` to TFC API curl; previously a slow or unresponsive TFC API would hang the step until the 15-minute job timeout
- `scripts/setup.sh` — `check_or_install()` now returns 1 on version mismatch (was silently returning 0, which prevented version-aware reinstall callers from firing); terraform and tflint blocks updated to differentiate "not installed" from "wrong version"
- `scripts/setup.sh` — `tfsec` installation replaced from unversioned `install_package tfsec` (package manager resolves to whatever is current) with `install_tfsec_versioned()` that downloads the exact `REQUIRED_TFSEC_VERSION` binary from GitHub releases
- `modules/stages/bootstrap/main.tf` — `roles/iam.securityAdmin` exception updated with detailed per-role justification explaining why it is the minimum required scope and why broader alternatives (`roles/resourcemanager.organizationAdmin`) were rejected; comment documents the circular dependency that prevents a custom role approach
- `modules/network/cloud-armor/variables.tf` — `default_rule_action` description expanded with security warning explaining the "allow" default (allowlist mode vs denylist mode), guidance on traffic impact of changing the default, and recommendation to review with adaptive protection before toggling in production
- **CRITICAL** `modules/governance/cloud-audit-logs/main.tf:80` — project-level log sink filter was `resource.type=project AND ...` which silently drops DATA_READ/DATA_WRITE/Admin Activity logs for GCE, GCS, Cloud SQL, BigQuery, etc. Fixed to `logName:"cloudaudit.googleapis.com"` (matches all audit log types for all services)
- **CRITICAL** `modules/stages/organization/main.tf:190` — `compute.vmExternalIpAccess` was applied as a boolean org policy; it is a LIST constraint. Using it via `boolean_policies` sent an invalid policy spec to the GCP API (silently ignored or rejected). Moved to `list_policies` with `deny_all = true`
- **CRITICAL** `modules/governance/billing/main.tf` — Cloud Functions gen1 `budget_notifier` violated the `cloudfunctions.requireVPCConnector` org policy enforced by the same landing zone. Upgraded to Cloud Functions gen2 (`google_cloudfunctions2_function`) with `vpc_connector` support
- **CRITICAL** `modules/governance/billing/main.tf:129` — SendGrid API key was injected as a plain `environment_variables` value (visible in GCP console and Terraform state). Replaced with `secret_environment_variables` block sourced from Secret Manager
- **CRITICAL** `modules/network/cloud-armor/main.tf:20-29` — hardcoded inline rule using deprecated `evaluatePreconfiguredExpr('cve-canary')` was always active regardless of `enable_log4j_protection` flag, making the optional resource dead code. Removed inline rule; the `log4j_protection` resource at priority 999 using `evaluatePreconfiguredWaf('log4j-v33-stable')` is now the sole Log4j guard and correctly honours the flag
- `modules/cloud-storage/main.tf` — `soft_delete_retention_seconds` field was declared in the `data_buckets` object type but never applied to any bucket resource. Now wired via `soft_delete_policy` block. Data buckets now also support optional `lifecycle_rule` via `retention_days` field
- `modules/cloud-storage/main.tf` — all three bucket resources now apply `var.labels`
- `modules/stages/workload/main.tf` — replaced authoritative `google_project_iam_binding` + `google_compute_subnetwork_iam_binding` with additive `google_project_iam_member` + `google_compute_subnetwork_iam_member`; authoritative bindings silently evict all unmanaged members on every apply
- `modules/stages/workload/main.tf:75` — GKE robot SA (`container-engine-robot`) was hardcoded in subnet bindings for all service projects, including those without GKE; the SA only exists after container.googleapis.com is activated, causing dangling IAM bindings. Now conditional on `var.enable_gke_network_user`
- `modules/monitoring/alert-policy/main.tf:239` — uptime check alert hardcoded `resource.type="uptime_url"` which fails for TCP uptime checks. Now uses `var.uptime_check_resource_type`
- `modules/governance/org-policy/main.tf:53` — custom constraint `name` field included parent path prefix, creating a double-path that the GCP API rejects. Fixed to short name only
- `modules/stages/projects/main.tf:72` — `google_monitoring_monitored_project.name` was set to project ID instead of required `locations/global/metricsScopes/<scope>/projects/<project>` format
- `modules/governance/kms/variables.tf:42` — rotation period validation used `replace(..., "s", "")` which silently breaks on `"90d"`, `"P90D"`, or suffixless values; replaced with explicit format regex check (`^[0-9]+s$`) and `trimsuffix` for the numeric range check
- `modules/governance/billing/main.tf` — `var.tags` renamed to `var.labels` throughout for consistency with every other module in this codebase
- `modules/stages/organization/main.tf:290` — `billing_export` BigQuery dataset was created without labels, blocking cost attribution and org policy targeting
- `.github/workflows/terraform-plan.yml:91` — `fail-fast: true` on the validate matrix cancelled all sibling jobs on first failure; changed to `fail-fast: false` so all root failures surface in one run
- `modules/host/main.tf` — `enable_log4j_protection` now passed through to the cloud_armor child module call (was silently ignored before)
- `modules/stages/workload/variables.tf` — `project_admin_roles` validation extended to block org/folder-level privileged roles in addition to primitive roles
- `modules/stages/organization/main.tf` — added `google_bigquery_dataset_iam_member` for Cloud Billing service agent (`billing-export@system.gserviceaccount.com`); without this the billing export silently fails with missing permissions
- `modules/stages/organization/main.tf` — audit log retention now uses `var.audit_log_retention_days` instead of hardcoded 365
- `envs/organization/providers.tf` — `impersonate_service_account` now wired to `var.terraform_admin_email` in both `google` and `google-beta` provider blocks (previously ran with personal credentials)
- `.github/workflows/reusable-security.yml` — tfsec Docker image pinned to `aquasec/tfsec:v1.28.6` (was floating `:latest`)
- `SECURITY.md` — corrected "730-day" claim to reflect configurable default (365 days) with compliance guidance
- `modules/cloud-storage/outputs.tf` — was empty; now exports `bucket_names`, `access_logs_bucket_name`, `logs_bucket_name`, `bucket_self_links`
- `envs/apps/providers.tf` — added explicit `provider "google-beta"` block (required for Firebase, API Gateway)
- `modules/stages/projects/variables.tf` — `suffix` variable now validated as lowercase hex
- `modules/network/dns/variables.tf` — `zone_name` format validation
- `modules/network/nat/variables.tf` — `name` format validation
- `modules/network/vpc/variables.tf` — `vpc_name` format validation
- `modules/iam/identity-group/variables.tf` — email format validation on group emails

### Breaking Changes

- **GCP roots renamed for cross-cloud naming symmetry** — `envs/organization` → `envs/gcp-organization`
  and `envs/apps` → `envs/gcp-workload`, mirroring the AWS `aws-organization` / `aws-workload` convention.
  The GCP control plane stays a single root (it folds security/network/KMS/audit into the org layer); only
  the names changed, not the layer topology.

  Consequences that require operator action:
  - **TFC workspaces must be renamed** to match: `organization` → `gcp-organization`, and each
    `apps-<env>` → `gcp-workload-<env>`. Renaming a workspace in Terraform Cloud preserves its state.
    Follow [`docs/runbooks/gcp-workspace-rename.md`](docs/runbooks/gcp-workspace-rename.md).
  - **Release tags changed**: `organization/vX.Y.Z` → `gcp-organization/vX.Y.Z` and
    `apps/<env>/vX.Y.Z` → `gcp-workload/<env>/vX.Y.Z` (enforced by `.github/workflows/terraform-apply.yml`).
  - **Makefile targets renamed**: `*-organization` → `*-gcp-organization`, `*-apps` → `*-gcp-workload`
    (e.g. `make plan-apps` → `make plan-gcp-workload`); `APP_WORKSPACE` now defaults to `gcp-workload-$(APP_ENV)`.
  - The `gcp-organization` root's WIF bootstrap now binds `gcp-workload-<env>` workspace names; downstream
    roots reading org state default `organization_workspace_name` to `gcp-organization`.

  No Terraform resource addresses change, so no `moved` blocks or `state mv` are needed — only the TFC
  workspace names and the backend `name`/`prefix` values.

- **`modules/governance/tags`** — `var.tags` type changed from `map(list(string))` to
  `map(object({values = list(string), description = optional(string, "Managed by Terraform")}))`.
  Callers must migrate using the following pattern:

  ```hcl
  # Before
  tags = {
    "environment" = ["dev", "prod"]
  }

  # After
  tags = {
    "environment" = {
      values = ["dev", "prod"]  # description is optional, defaults to "Managed by Terraform"
    }
  }
  ```

  The `stages/organization` caller and `governance/tags/examples/basic` have been updated.
  Any direct caller of `modules/governance/tags` must update before the next `terraform apply`.

---

## Initial baseline (pre-1.0 — not yet tagged)

> Snapshot of the initial landing-zone build (baseline dated 2026-01-15). This has **not**
> been cut as a Git tag or GitHub Release yet; it is documented here for provenance. The
> first tagged release will use the `gcp-organization/vX.Y.Z` scheme described at the top.

### Added

- Initial landing zone baseline
- Bootstrap stage: Terraform admin project, WIF pools for GitHub Actions and Terraform Cloud
- Organization stage: folders, org policies, billing export, audit logs, SCC notifications, essential contacts
- Projects stage: environment project factory with monitoring scope
- Network hub stage: hub-and-spoke VPC topology with DNS forwarding
- Workload module: Shared VPC service project attachment with subnet IAM
- `modules/host` — full-featured VPC module (networking, NAT, VPN, Interconnect, VPC-SC, CDN, Cloud Armor, packet mirroring, internal LB)
- 10 governance modules (KMS, billing, org policy, SCC, tags, audit logs, IAM, roles, service accounts, WIF)
- 15 network modules (VPC, subnet, DNS, NAT, VPN, peering, flow logs, firewall, CDN, internal LB, Interconnect, Cloud Armor, hierarchical firewall, VPC-SC, private service access/connect)
- GitHub Actions CI/CD: plan (fmt, validate, lint, security), apply (TFC gate + release), security scan (TFSec, Checkov, Trivy, Gitleaks), documentation auto-gen
- Pre-commit hooks: `terraform fmt`, `terraform validate`, `terraform-docs`, TFLint, TFSec, Checkov, Gitleaks
- Makefile: fmt-check, validate-all, lint, security, docs, test, ci targets
- QUICK_START.md, ARCHITECTURE.md, network-topology.md, CONTRIBUTING.md, TROUBLESHOOTING.md
- Runbooks: add-environment, break-glass, cidr-expansion, kms-rotation, service-team-onboarding
- CODEOWNERS, PR template, issue templates (bug, feature, security)

[Unreleased]: https://github.com/EdwinKassier/Ashes-Devops-Tools/commits/main
