<div align="center">

<img src="https://www.edwinkassier.com/Assets/Monogram.png" alt="Ashes Project Monogram" width="100" height="100">

# Ashes DevOps Tools

**Production-grade Terraform infrastructure for AWS, GCP, Supabase, and Vercel**

[![Terraform](https://img.shields.io/badge/Terraform-1.9%2B-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)
[![AWS](https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonwebservices&logoColor=white)](https://aws.amazon.com)
[![Google Cloud](https://img.shields.io/badge/Google_Cloud-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)](https://cloud.google.com)
[![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![Vercel](https://img.shields.io/badge/Vercel-000000?style=for-the-badge&logo=vercel&logoColor=white)](https://vercel.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

<br/>

[![Terraform Validation](https://github.com/EdwinKassier/Ashes-Devops-Tools/actions/workflows/terraform-plan.yml/badge.svg)](https://github.com/EdwinKassier/Ashes-Devops-Tools/actions/workflows/terraform-plan.yml)
[![Security Scan](https://github.com/EdwinKassier/Ashes-Devops-Tools/actions/workflows/security-scan.yml/badge.svg)](https://github.com/EdwinKassier/Ashes-Devops-Tools/actions/workflows/security-scan.yml)
[![Pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?style=flat-square&logo=pre-commit)](https://pre-commit.com)
[![Modules](https://img.shields.io/badge/modules-89-blueviolet?style=flat-square)](modules/)
[![Tests](https://img.shields.io/badge/test_suites-153-blue?style=flat-square)](modules/)

<sub>Modules/test-suite counts above are hand-maintained, not live badges. Verify: <code>find modules -name main.tf -not -path '*/examples/*' -not -path '*/.terraform/*' | wc -l</code> (modules) and <code>find modules envs -name '*.tftest.hcl' -not -path '*/.terraform/*' | wc -l</code> (test suites). Last verified 2026-07-09: 89 modules, 153 test suites.</sub>

</div>

---

## Overview

**Ashes DevOps Tools** is a fully-tested, security-scanned Terraform platform covering four deployment surfaces — deploy any combination:

| Surface | What it manages |
|:--------|:----------------|
| **GCP Landing Zone** | Organization hierarchy, IAM, networking hub, VPC-SC, KMS, audit logs |
| **Application Environments** | Per-env host projects, Shared VPC, Cloud Armor, VPN, Interconnect |
| **AWS Landing Zone** | Multi-account SRA org + guardrails (SCP/RCP/declarative), security baseline (GuardDuty/Security Hub/Config/CloudTrail/Access Analyzer/Security Lake), Transit Gateway network, IAM Identity Center, org backup, cost governance |
| **SaaS Workloads** | Supabase projects + vault secrets, Vercel projects + three-tier environments |

**Execution model:** Terraform Cloud owns all live state and applies. GitHub Actions validates every PR. Tags trigger release metadata — never direct applies.

---

## Quick Start

```bash
# 1. Clone and install repo tooling
git clone https://github.com/EdwinKassier/Ashes-Devops-Tools.git
cd Ashes-Devops-Tools
make install && make pre-commit-install

# 2. Authenticate (only the clouds whose workspaces you apply)
gcloud auth application-default login     # GCP roots (organization, apps)
export SUPABASE_ACCESS_TOKEN="sbp_..."   # required for supabase modules
export VERCEL_API_TOKEN="..."            # required for vercel modules
# AWS roots use TFC dynamic credentials (TFC_AWS_PROVIDER_AUTH + TFC_AWS_RUN_ROLE_ARN)
# or AWS_PROFILE for local runs — see the AWS Bootstrap runbook for the full flow.

# 3. Run the local validation suite (no cloud credentials needed for tests)
make ci
```

> Full bootstrap sequence, backend config, and first apply: **[Quick Start Guide →](docs/guides/QUICK_START.md)**

---

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│                   GitHub Actions (CI)                   │
│  fmt · validate · lint · tfsec · checkov · terraform-docs│
└────────────────────────┬────────────────────────────────┘
                         │ PR gates
┌────────────────────────▼────────────────────────────────┐
│                  Terraform Cloud (CD)                   │
│              Remote state · Plan · Apply                │
│         one root = one workspace (per cloud)            │
└──────┬───────────────────────┬───────────────────┬──────┘
       │ GCP                   │ AWS               │ SaaS
┌──────▼──────────┐   ┌────────▼─────────┐   ┌─────▼──────┐
│ envs/organization│   │ envs/aws-*       │   │ envs/saas  │
│ envs/apps        │   │ organization →   │   │ Supabase   │
│ (control plane,  │   │ security →       │   │ and/or     │
│  host/spoke VPC, │   │ network →        │   │ Vercel     │
│  KMS, WIF)       │   │ identity →       │   │ (no cloud  │
│                  │   │ shared-services →│   │  provider) │
│                  │   │ backup →         │   │            │
│                  │   │ workload         │   │            │
└─────────────────┘   └──────────────────┘   └────────────┘
```

> AWS is a multi-account SRA landing zone with its own layered roots. Full detail: **[AWS Landing Zone →](docs/architecture/aws-landing-zone.md)**. Cloud selection is which workspaces you apply, not a runtime flag: **[Provider Selection →](docs/architecture/provider-selection.md)**.

### Choosing providers

Deploy **any combination** of `{aws, gcp, supabase, vercel}`. Each cloud lives in its own root (and TFC workspace), so an unused cloud's provider is physically absent from what you apply — a `provider` block can't be conditional, and Terraform authenticates any referenced provider even at `count = 0`. **Cloud selection is therefore which workspaces you apply, not a runtime `enable_<cloud>` flag** (`enable_*` only gates features within a root). Every subset — including AWS-only, GCP-only, or SaaS-only — is just the union of the per-cloud workspaces and their credentials.

> Full rationale, root inventory, minimum AWS footprint, and the any-combination matrix: **[Provider Selection →](docs/architecture/provider-selection.md)**

---

## Module Library

89 modules across 8 categories, each with auto-generated docs and `mock_provider` tests.

### SaaS Integrations

| Module | Provider | Purpose |
|:-------|:---------|:--------|
| [`supabase/project`](modules/supabase/project/) | Supabase | Project provisioning with lifecycle guard |
| [`supabase/settings`](modules/supabase/settings/) | Supabase | Auth + API settings management |
| [`supabase/environment`](modules/supabase/environment/) | Supabase | Composite: project + settings + API keys |
| [`supabase/vault-secrets`](modules/supabase/vault-secrets/) | Supabase + Node.js | Vault bootstrap and secret reconciliation |
| [`vercel/project`](modules/vercel/project/) | Vercel | Three-environment project with drift resistance |
| [`stages/saas-workload`](modules/stages/saas-workload/) | All three | Full SaaS environment in one call |

### Google Cloud

<details>
<summary><strong>Networking (19 modules)</strong></summary>

| Module | Purpose |
|:-------|:--------|
| [`network/vpc`](modules/network/vpc/) | Virtual Private Cloud |
| [`network/subnet`](modules/network/subnet/) | Standardized subnet creation |
| [`network/dns`](modules/network/dns/) | Private/public DNS zones |
| [`network/network-firewall`](modules/network/network-firewall/) | Network security rules |
| [`network/hierarchical-firewall`](modules/network/hierarchical-firewall/) | Policy-based org firewall |
| [`network/cloud-armor`](modules/network/cloud-armor/) | WAF / DDoS protection |
| [`network/api-gateway`](modules/network/api-gateway/) | API management |
| [`network/cdn`](modules/network/cdn/) | Content delivery network |
| [`network/vpc-peering`](modules/network/vpc-peering/) | VPC peering connections |
| [`network/private-service-connect`](modules/network/private-service-connect/) | Private Service Connect |
| [`network/private-service-access`](modules/network/private-service-access/) | Private Service Access |
| [`network/vpn`](modules/network/vpn/) | HA-VPN with BGP |
| [`network/interconnect`](modules/network/interconnect/) | Dedicated Interconnect |
| [`network/internal-lb`](modules/network/internal-lb/) | Internal Load Balancer |
| [`network/nat`](modules/network/nat/) | Cloud NAT |
| [`network/packet-mirroring`](modules/network/packet-mirroring/) | Packet Mirroring |
| [`network/shared-vpc-service`](modules/network/shared-vpc-service/) | Shared VPC service attachment |
| [`network/vpc-flow-logs`](modules/network/vpc-flow-logs/) | VPC Flow Logs |
| [`network/vpc-sc`](modules/network/vpc-sc/) | VPC Service Controls |

</details>

<details>
<summary><strong>IAM & Security (6 modules)</strong></summary>

| Module | Purpose |
|:-------|:--------|
| [`iam/organization`](modules/iam/organization/) | Org-level IAM bindings |
| [`iam/role`](modules/iam/role/) | Custom IAM roles |
| [`iam/service-account`](modules/iam/service-account/) | Service account lifecycle |
| [`iam/workload-identity`](modules/iam/workload-identity/) | Workload Identity Federation |
| [`iam/identity-group`](modules/iam/identity-group/) | Google Cloud Identity groups |
| [`iam/identity-group-memberships`](modules/iam/identity-group-memberships/) | Group membership management |

</details>

<details>
<summary><strong>Governance (6 modules)</strong></summary>

| Module | Purpose |
|:-------|:--------|
| [`governance/billing`](modules/governance/billing/) | Budget alerts |
| [`governance/cloud-audit-logs`](modules/governance/cloud-audit-logs/) | Centralized audit logging |
| [`governance/kms`](modules/governance/kms/) | Customer-managed encryption keys |
| [`governance/org-policy`](modules/governance/org-policy/) | Organization policies |
| [`governance/scc`](modules/governance/scc/) | Security Command Center notifications |
| [`governance/tags`](modules/governance/tags/) | Resource tag keys and values |

</details>

<details>
<summary><strong>Stages & Platform (12 orchestration modules + 1 top-level compatibility wrapper)</strong></summary>

| Module | Purpose |
|:-------|:--------|
| [`stages/bootstrap`](modules/stages/bootstrap/) | Admin project, WIF pool, Terraform SA |
| [`stages/organization`](modules/stages/organization/) | Folders, org policy, audit logs, budgets |
| [`stages/projects`](modules/stages/projects/) | Shared + host projects |
| [`stages/network-hub`](modules/stages/network-hub/) | Hub VPC + DNS hub |
| [`stages/workload`](modules/stages/workload/) | Shared VPC service project attachment |
| [`stages/saas-workload`](modules/stages/saas-workload/) | Supabase + Vercel full-stack environment |
| [`stages/aws-organization`](modules/stages/aws-organization/) | AWS Organizations, OUs, SCPs, cost governance |
| [`stages/aws-security`](modules/stages/aws-security/) | GuardDuty, Security Hub, Config, CloudTrail, delegated admin |
| [`stages/aws-network-hub`](modules/stages/aws-network-hub/) | Transit Gateway, IPAM, Network Firewall, Route 53 Resolver |
| [`stages/aws-shared-services`](modules/stages/aws-shared-services/) | Log archive, KMS, private CA, Systems Manager |
| [`stages/aws-backup`](modules/stages/aws-backup/) | Org-wide AWS Backup vaults and policies |
| [`stages/aws-workload`](modules/stages/aws-workload/) | Per-account workload VPC + baseline |
| [`host`](modules/host/) | Top-level compatibility wrapper for `envs/apps` (not under `modules/stages/`) — composes networking, security, and governance primitives |

</details>

<details>
<summary><strong>Storage, Compute & Firebase (3 modules)</strong></summary>

| Module | Purpose |
|:-------|:--------|
| [`cloud-storage`](modules/cloud-storage/) | GCS buckets with log separation and optional CMEK |
| [`artifact-registry`](modules/artifact-registry/) | Container/package registries |
| [`firebase/project`](modules/firebase/project/) | Firebase project setup with Apple, Android, and Web app targets |

</details>

<details>
<summary><strong>Monitoring (2 modules)</strong></summary>

| Module | Purpose |
|:-------|:--------|
| [`monitoring/alert-policy`](modules/monitoring/alert-policy/) | Cloud Monitoring alert policies and notification channels |
| [`monitoring/compute-dashboard`](modules/monitoring/compute-dashboard/) | Compute observability dashboards |

</details>

### Amazon Web Services

<details>
<summary><strong>AWS Landing Zone (35 modules)</strong></summary>

| Module | Purpose |
|:-------|:--------|
| [`aws/organization`](modules/aws/organization/) | AWS Organizations, OUs, root config |
| [`aws/organization-policy`](modules/aws/organization-policy/) | Service Control Policies (SCPs) |
| [`aws/account`](modules/aws/account/) | Member account provisioning |
| [`aws/account-baseline`](modules/aws/account-baseline/) | Per-account baseline guardrails |
| [`aws/cost-governance`](modules/aws/cost-governance/) | Budgets, cost anomaly detection, allocation tags |
| [`aws/service-quotas`](modules/aws/service-quotas/) | Service quota requests |
| [`aws/iam-organizations-features`](modules/aws/iam-organizations-features/) | Org-wide IAM features |
| [`aws/iam-identity-center`](modules/aws/iam-identity-center/) | IAM Identity Center (SSO) |
| [`aws/iam-role`](modules/aws/iam-role/) | IAM roles |
| [`aws/access-analyzer-org`](modules/aws/access-analyzer-org/) | Org-level IAM Access Analyzer |
| [`aws/guardduty-org`](modules/aws/guardduty-org/) | Org-wide GuardDuty |
| [`aws/securityhub-org`](modules/aws/securityhub-org/) | Org-wide Security Hub |
| [`aws/config-org`](modules/aws/config-org/) | Org-wide AWS Config |
| [`aws/cloudtrail-org`](modules/aws/cloudtrail-org/) | Org-wide CloudTrail |
| [`aws/securitylake`](modules/aws/securitylake/) | Amazon Security Lake |
| [`aws/security-delegated-admin`](modules/aws/security-delegated-admin/) | Delegated administrator registration |
| [`aws/org-security-service`](modules/aws/org-security-service/) | Org security service enablement |
| [`aws/security-notifications`](modules/aws/security-notifications/) | Security finding notifications |
| [`aws/firewall-manager-org`](modules/aws/firewall-manager-org/) | Org-wide Firewall Manager |
| [`aws/edge-security`](modules/aws/edge-security/) | Edge / WAF security |
| [`aws/secrets-baseline`](modules/aws/secrets-baseline/) | Secrets Manager baseline |
| [`aws/incident-response`](modules/aws/incident-response/) | Incident response tooling |
| [`aws/kms-key`](modules/aws/kms-key/) | Customer-managed KMS keys |
| [`aws/private-ca`](modules/aws/private-ca/) | AWS Private Certificate Authority |
| [`aws/systems-manager`](modules/aws/systems-manager/) | Systems Manager configuration |
| [`aws/log-archive-bucket`](modules/aws/log-archive-bucket/) | Centralized log archive bucket |
| [`aws/vpc`](modules/aws/vpc/) | VPC with subnets and routing |
| [`aws/vpc-endpoints`](modules/aws/vpc-endpoints/) | VPC interface/gateway endpoints |
| [`aws/transit-gateway`](modules/aws/transit-gateway/) | Transit Gateway hub |
| [`aws/ipam`](modules/aws/ipam/) | IP Address Manager |
| [`aws/network-firewall`](modules/aws/network-firewall/) | AWS Network Firewall |
| [`aws/network-access-analyzer`](modules/aws/network-access-analyzer/) | Network Access Analyzer |
| [`aws/route53-resolver`](modules/aws/route53-resolver/) | Route 53 Resolver rules/endpoints |
| [`aws/backup-vault`](modules/aws/backup-vault/) | AWS Backup vault |
| [`aws/backup-org-policy`](modules/aws/backup-org-policy/) | Org-wide backup policies |

</details>

---

## Commands

```bash
make ci                    # Full local pipeline (fmt + docs + validate + lint + security + test)
make fmt                   # Format all Terraform files
make test                  # Run all 153 .tftest.hcl suites (no cloud creds needed)
make validate-all          # terraform validate across all roots
make lint                  # TFLint with GCP ruleset
make security              # tfsec + Checkov
make docs                  # Regenerate all module READMEs via terraform-docs
make docs-check            # Verify no README is stale
make plan-organization     # Plan control-plane changes
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars
```

---

## CI / CD

| Workflow | Trigger | What it does |
|:---------|:--------|:-------------|
| [`terraform-plan.yml`](.github/workflows/terraform-plan.yml) | Pull Request | fmt · docs-check · validate · lint · tfsec · checkov |
| [`terraform-apply.yml`](.github/workflows/terraform-apply.yml) | Tags (`organization/v*`, `apps/*/v*`) | Verify TFC run → publish GitHub release |
| [`security-scan.yml`](.github/workflows/security-scan.yml) | Push + weekly | tfsec · checkov · Trivy · Gitleaks → SARIF |
| [`documentation.yml`](.github/workflows/documentation.yml) | Module `*.tf` changes | Auto-generate docs → open PR |
| [`drift-detection.yml`](.github/workflows/drift-detection.yml) | Scheduled | Detect infrastructure drift |

**Releasing:**

```bash
git tag -a organization/v1.2.0 -m "Release organization v1.2.0"
git push origin organization/v1.2.0
```

---

## Documentation

| Document | Description |
|:---------|:------------|
| [Documentation Index](docs/INDEX.md) | Complete navigation hub |
| [Quick Start](docs/guides/QUICK_START.md) | Bootstrap, creds, first apply |
| [Architecture](docs/architecture/ARCHITECTURE.md) | Roots, modules, execution model |
| [AWS Landing Zone](docs/architecture/aws-landing-zone.md) | Multi-account SRA model, layer map, SRA conformance checklist |
| [Adding a Cloud](docs/architecture/adding-a-cloud.md) | Per-cloud-root contract for extending the platform |
| [Provider Selection](docs/architecture/provider-selection.md) | Any-combination cloud matrix, per-cloud-root model |
| [Network Topology](docs/architecture/network-topology.md) | Hub-spoke layout, VPC-SC, WIF flows |
| [Troubleshooting](docs/guides/TROUBLESHOOTING.md) | Common errors including Supabase/Vercel |
| [Branch Protection](docs/guides/BRANCH_PROTECTION.md) | GitHub ruleset configuration |
| [CLAUDE.md](CLAUDE.md) | Onboarding guide for AI agents |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development workflow and standards |
| [CHANGELOG.md](CHANGELOG.md) | Release notes |

**GCP runbooks:** [Add Environment](docs/runbooks/add-environment.md) · [Service Team Onboarding](docs/runbooks/service-team-onboarding.md) · [KMS Rotation](docs/runbooks/kms-rotation.md) · [CIDR Expansion](docs/runbooks/cidr-expansion.md) · [Break Glass](docs/runbooks/break-glass.md)

**AWS runbooks:** [AWS Bootstrap](docs/runbooks/aws-bootstrap.md) · [AWS Add Account](docs/runbooks/aws-add-account.md) · [AWS Break Glass](docs/runbooks/aws-break-glass.md) · [AWS Incident Response](docs/runbooks/aws-incident-response.md) · [AWS Teardown](docs/runbooks/aws-teardown.md)

---

## Security

> Report vulnerabilities via [SECURITY.md](SECURITY.md) — do not open a public issue.

- **PR gates:** TFSec + Checkov on every pull request
- **Scheduled scans:** Trivy (container/IaC) + Gitleaks (secrets) weekly
- **SARIF upload:** All findings surface in the GitHub Security tab
- **Inline skips only:** False positives are suppressed with `# tfsec:ignore` / `# checkov:skip` on the specific resource — never via global skip lists

---

<div align="center">

Built with [Terraform](https://terraform.io) · [AWS](https://aws.amazon.com) · [Google Cloud](https://cloud.google.com) · [Supabase](https://supabase.com) · [Vercel](https://vercel.com)

</div>
