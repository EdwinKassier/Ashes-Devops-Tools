# Changelog

All notable changes to this landing zone are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Releases are tagged as `organization/vX.Y.Z` and `apps/<env>/vX.Y.Z`.

---

## [Unreleased]

### Added
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
