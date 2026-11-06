# Changelog

All notable changes to this landing zone are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the repository
follows [Semantic Versioning](https://semver.org/) (pre-1.0: a minor bump may break).

**Versioning.** The repository as a whole is released as `vX.Y.Z` by
[release-please](https://github.com/googleapis/release-please) (`.github/workflows/release.yml`,
`release-please-config.json`): every merge to `main` updates a release PR whose version and notes
are derived from Conventional Commit subjects (`feat:` → minor, `fix:` → patch while pre-1.0).
Merging that PR tags `vX.Y.Z` and publishes the GitHub Release. These repo-version tags are
distinct from the per-workspace **deployment** tags (`gcp-organization/vX.Y.Z`,
`gcp-workload/<env>/vX.Y.Z`, `aws-*/vX.Y.Z`, …) that `terraform-apply.yml` uses to record
release metadata for a Terraform Cloud run.

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

### Wave A of the [2026-11-06 enterprise boilerplate audit](docs/audit/2026-11-06-enterprise-boilerplate-audit.md)

- **The management aws-security role cannot disable org detection (S-H1).** Disabling delegated
  admins or trusted access and deregistering delegated admins now need the off-by-default
  `enable_security_service_teardown` gate, which is a separate inline policy. The role is
  also denied trail untagging and resource-policy edits, CIS-alarm deletion and disabling,
  and trail log-group, log-stream, metric-filter and retention deletion. `aws-organization` owns the new
  `org-guard-alerts` topic (us-east-1, CMK-encrypted, `aws.guard_alert_emails`). Its EventBridge
  rule covers those calls and org-trail selector and tag changes, with forwarding from every
  other enabled region.

#### Fixed

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

Remediation of the [2026-11-05 enterprise boilerplate audit](docs/audit/2026-11-05-enterprise-boilerplate-audit.md).

### Added

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

### Changed

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

- `modules/gcp/stages/host` — the network god-module facade (no in-repo callers) is **removed in
  `v1.0.0`**. Migrate to `stages/net-hub`, `stages/dns-anchor` and `stages/net-spoke`; see the module
  README for the per-use mapping and reference `moved.tf` files.

### Fixed

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
