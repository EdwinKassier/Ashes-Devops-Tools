# Changelog

All notable changes to this landing zone are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Releases are tagged as `organization/vX.Y.Z` and `apps/<env>/vX.Y.Z`.

---

## [Unreleased]

### Added
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
