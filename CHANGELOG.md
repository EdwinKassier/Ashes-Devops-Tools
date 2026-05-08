# Changelog

All notable changes to this landing zone are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Releases are tagged as `organization/vX.Y.Z` and `apps/<env>/vX.Y.Z`.

---

## [Unreleased]

### Added
- `modules/stages/bootstrap/main.tf` — `google_billing_account_iam_member` grants `roles/billing.costsManager` to the Terraform admin SA; without this, `google_billing_budget` creation fails at apply time with a permissions error even when folder-level roles are present
- `modules/governance/org-policy/variables.tf` — duplicate constraint validation on both `boolean_policies` and `list_policies`; prevents silent last-wins overwrite when the same constraint appears twice
- `modules/governance/org-policy/tests/validation.tftest.hcl` — 2 new tests rejecting duplicate boolean and list policy constraints
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
- `modules/monitoring/alert_policy/variables.tf` — `uptime_check_resource_type` variable (`uptime_url` / `uptime_tcp`); `webhook_notification_channel_ids` output marked sensitive
- `modules/cloud_storage/variables.tf` — `labels` variable; `retention_days` per-bucket field in `data_buckets` object type
- `modules/governance/billing/variables.tf` — `vpc_connector` variable for org-policy compliance; `labels` variable (replaces deprecated `tags`)
- `modules/monitoring/alert_policy` — new module: Cloud Monitoring alert policies and notification channels (CPU, memory, Cloud Run 5xx error rate, P99 latency, uptime, log-based); email + webhook (Slack/PagerDuty) notification channels; 22 mock_provider validation tests
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
- `envs/organization/variables.tf` — `github_org` and `github_repo` no longer have personal account defaults; removed to prevent accidentally trusting wrong org when forking
- `modules/host/variables.tf` — `vpn_shared_secret` default changed from `""` to `null` to force explicit configuration
- `templates/module/versions.tf` — constraint updated to `~> 1.9` (consistent with all modules)
- `terraform-apply.yml` — `permissions: contents: write` scoped to `release` job only; `verify-run` job uses `contents: read`
- All GitHub Actions SHA-pinned (removed mutable `@master`, `@v2` references)
- `documentation.yml` — replaced direct `git push` to main with `peter-evans/create-pull-request` PR flow
- Checkov global skip list replaced with per-resource inline suppressions
- `envs/organization/moved.tf` — added cleanup instructions (safe to delete after first migration apply)

### Fixed
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
- `.github/dependabot.yml` — added `modules/monitoring/alert_policy` and `modules/monitoring/alert_policy/examples/basic` (previously missing; provider updates went untracked)
- `Makefile` — `make security` and `make security-report` now pass `--config-file .checkov.yaml` to both Checkov invocations, matching CI behaviour; previously local runs produced different results than CI
- `Makefile` — `make clean` no longer deletes committed `.terraform.lock.hcl` files (was deleting all lock files outside `envs/`); separated into a guarded `make clean-locks` target
- `.tflint.hcl` — Google plugin bumped from `0.39.0` to `0.40.0`
- `envs/apps/variables.tf` — `monthly_budget_limit` description updated to explicitly state that `0` disables budget alerts; added `>= 0` validation with clear error message
- `modules/governance/kms/variables.tf` — rotation period upper bound relaxed from `7776000s` (90 days) to `31536000s` (365 days) to allow annual rotation for HSM-backed keys; comment documents NIST SP 800-57 recommendation for software keys
- `.github/workflows/terraform-apply.yml` — added `--max-time 30 --connect-timeout 10` to TFC API curl; previously a slow or unresponsive TFC API would hang the step until the 15-minute job timeout
- `scripts/setup.sh` — `check_or_install()` now returns 1 on version mismatch (was silently returning 0, which prevented version-aware reinstall callers from firing); terraform and tflint blocks updated to differentiate "not installed" from "wrong version"
- `scripts/setup.sh` — `tfsec` installation replaced from unversioned `install_package tfsec` (package manager resolves to whatever is current) with `install_tfsec_versioned()` that downloads the exact `REQUIRED_TFSEC_VERSION` binary from GitHub releases
- `modules/stages/bootstrap/main.tf` — `roles/iam.securityAdmin` exception updated with detailed per-role justification explaining why it is the minimum required scope and why broader alternatives (`roles/resourcemanager.organizationAdmin`) were rejected; comment documents the circular dependency that prevents a custom role approach
- `modules/network/cloud_armor/variables.tf` — `default_rule_action` description expanded with security warning explaining the "allow" default (allowlist mode vs denylist mode), guidance on traffic impact of changing the default, and recommendation to review with adaptive protection before toggling in production
- **CRITICAL** `modules/governance/cloud-audit-logs/main.tf:80` — project-level log sink filter was `resource.type=project AND ...` which silently drops DATA_READ/DATA_WRITE/Admin Activity logs for GCE, GCS, Cloud SQL, BigQuery, etc. Fixed to `logName:"cloudaudit.googleapis.com"` (matches all audit log types for all services)
- **CRITICAL** `modules/stages/organization/main.tf:190` — `compute.vmExternalIpAccess` was applied as a boolean org policy; it is a LIST constraint. Using it via `boolean_policies` sent an invalid policy spec to the GCP API (silently ignored or rejected). Moved to `list_policies` with `deny_all = true`
- **CRITICAL** `modules/governance/billing/main.tf` — Cloud Functions gen1 `budget_notifier` violated the `cloudfunctions.requireVPCConnector` org policy enforced by the same landing zone. Upgraded to Cloud Functions gen2 (`google_cloudfunctions2_function`) with `vpc_connector` support
- **CRITICAL** `modules/governance/billing/main.tf:129` — SendGrid API key was injected as a plain `environment_variables` value (visible in GCP console and Terraform state). Replaced with `secret_environment_variables` block sourced from Secret Manager
- **CRITICAL** `modules/network/cloud_armor/main.tf:20-29` — hardcoded inline rule using deprecated `evaluatePreconfiguredExpr('cve-canary')` was always active regardless of `enable_log4j_protection` flag, making the optional resource dead code. Removed inline rule; the `log4j_protection` resource at priority 999 using `evaluatePreconfiguredWaf('log4j-v33-stable')` is now the sole Log4j guard and correctly honours the flag
- `modules/cloud_storage/main.tf` — `soft_delete_retention_seconds` field was declared in the `data_buckets` object type but never applied to any bucket resource. Now wired via `soft_delete_policy` block. Data buckets now also support optional `lifecycle_rule` via `retention_days` field
- `modules/cloud_storage/main.tf` — all three bucket resources now apply `var.labels`
- `modules/stages/workload/main.tf` — replaced authoritative `google_project_iam_binding` + `google_compute_subnetwork_iam_binding` with additive `google_project_iam_member` + `google_compute_subnetwork_iam_member`; authoritative bindings silently evict all unmanaged members on every apply
- `modules/stages/workload/main.tf:75` — GKE robot SA (`container-engine-robot`) was hardcoded in subnet bindings for all service projects, including those without GKE; the SA only exists after container.googleapis.com is activated, causing dangling IAM bindings. Now conditional on `var.enable_gke_network_user`
- `modules/monitoring/alert_policy/main.tf:239` — uptime check alert hardcoded `resource.type="uptime_url"` which fails for TCP uptime checks. Now uses `var.uptime_check_resource_type`
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
- `modules/cloud_storage/outputs.tf` — was empty; now exports `bucket_names`, `access_logs_bucket_name`, `logs_bucket_name`, `bucket_self_links`
- `envs/apps/providers.tf` — added explicit `provider "google-beta"` block (required for Firebase, API Gateway)
- `modules/stages/projects/variables.tf` — `suffix` variable now validated as lowercase hex
- `modules/network/dns/variables.tf` — `zone_name` format validation
- `modules/network/nat/variables.tf` — `name` format validation
- `modules/network/vpc/variables.tf` — `vpc_name` format validation
- `modules/iam/identity_group/variables.tf` — email format validation on group emails

---

## [organization/v1.0.0] — 2026-01-15

### Added
- Initial landing zone release
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

[Unreleased]: https://github.com/EdwinKassier/Ashes-Devops-Tools/compare/organization/v1.0.0...HEAD
[organization/v1.0.0]: https://github.com/EdwinKassier/Ashes-Devops-Tools/releases/tag/organization/v1.0.0
