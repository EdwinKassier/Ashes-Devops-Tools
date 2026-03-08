<div align="center">

<img src="https://www.edwinkassier.com/Assets/Monogram.png" alt="Ashes Project Monogram" width="120" height="120">

# Ashes DevOps Tools

**Infrastructure as Code for scalable, secure, and maintainable cloud architecture**

[![Terraform](https://img.shields.io/badge/Terraform-1.6%2B-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)
[![GCP](https://img.shields.io/badge/Google_Cloud-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)](https://cloud.google.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

<div align="center">
  <a href="https://github.com/terraform-linters/tflint"><img src="https://img.shields.io/badge/TFLint-Passing-success?style=flat-square" alt="TFLint"/></a>
  <a href="https://github.com/aquasecurity/tfsec"><img src="https://img.shields.io/badge/TFSec-Passing-success?style=flat-square" alt="TFSec"/></a>
  <a href="https://www.checkov.io/"><img src="https://img.shields.io/badge/Checkov-Passing-success?style=flat-square" alt="Checkov"/></a>
  <a href="https://github.com/pre-commit/pre-commit"><img src="https://img.shields.io/badge/pre--commit-enabled-brightgreen?style=flat-square&logo=pre-commit" alt="Pre-commit"/></a>
</div>

</div>

---

## Overview

The **Ashes DevOps Tools** repository provides a Terraform-based Google Cloud platform with two supported deployable roots:

- `envs/organization` for control-plane resources such as folders, shared projects, org policies, and hub networking.
- `envs/apps` for per-environment application infrastructure using Terraform Cloud workspaces named `apps-<env>`.

Terraform Cloud is the only live plan/apply control plane. GitHub Actions validates code and publishes release metadata; it does not apply infrastructure directly.

---

## Quick Start

Get started from the repository root:

```bash
# 1. Install local tooling used by this repo
make install && make pre-commit-install

# 2. Install Terraform separately, then authenticate with GCP
gcloud auth application-default login

# 3. Initialize the supported roots
terraform -chdir=envs/organization init
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps init

# 4. Run the fast local checks
make fmt-check
make docs-check
make security
```

See [docs/guides/QUICK_START.md](docs/guides/QUICK_START.md) for the full setup flow and the optional deeper checks (`make validate-all`, `make lint`) that require additional local prerequisites.

---

## Documentation

### **Essential Guides**

| Document | Description |
|:---|:---|
| **[Documentation Index](docs/INDEX.md)** | Complete navigation for all documentation |
| **[Quick Start Guide](docs/guides/QUICK_START.md)** | Local setup, initialization, and common commands |
| **[System Architecture](docs/architecture/ARCHITECTURE.md)** | Current roots, modules, and execution model |
| **[Troubleshooting Guide](docs/guides/TROUBLESHOOTING.md)** | Common issues and solutions |

### **Configuration & Workflows**

| Type | Location | Description |
|:---|:---|:---|
| **Development Commands** | [Makefile](Makefile) | Supported local entrypoints for validation, docs, and plans |
| **Pre-commit Hooks** | [.pre-commit-config.yaml](.pre-commit-config.yaml) | Automated formatting and repository checks |
| **Linting Configuration** | [.tflint.hcl](.tflint.hcl) | Terraform linting rules |
| **Documentation Config** | [.terraform-docs.yml](.terraform-docs.yml) | Auto-generation configuration |
| **Editor Settings** | [.editorconfig](.editorconfig) | Consistent coding styles |
| **CI/CD Workflows** | [.github/workflows/](.github/workflows/) | Validation, documentation, release metadata, and security workflows |
| **Issue Templates** | [.github/ISSUE_TEMPLATE/](.github/ISSUE_TEMPLATE/) | Bug reports, features, security |
| **Pull Requests** | [.github/pull_request_template.md](.github/pull_request_template.md) | PR template |
| **Code Ownership** | [.github/CODEOWNERS](.github/CODEOWNERS) | Code ownership rules |
| **Dependencies** | [.github/dependabot.yml](.github/dependabot.yml) | Automated dependency updates |

---

## Repository Structure

### **Environments**

```text
envs/
├── organization/   # Control-plane root (folders, projects, policies)
└── apps/           # Single app-environment root (TF_WORKSPACE=apps-<env>)
```

### **Modules**

Terraform modules are organized by category:

#### **Compute & Applications**
- `modules/firebase/` - Firebase services
- `modules/monitoring/` - Compute Dashboard

#### **Storage & Data**
- `modules/cloud_storage/` - Object storage
- `modules/artifact_registry/` - Container registry

#### **Networking**
- `modules/network/vpc/` - Virtual private cloud
- `modules/network/subnet/` - Standardized subnet creation
- `modules/network/network-firewall/` - Network security
- `modules/network/hierarchical-firewall/` - Policy-based firewall
- `modules/network/cloud_armor/` - DDoS protection
- `modules/network/api_gateway/` - API management
- `modules/network/cdn/` - Content delivery network
- `modules/network/dns/` - Cloud DNS private/public zones
- `modules/network/vpc-peering/` - VPC peering connections
- `modules/network/private-service-connect/` - Private Service Connect
- `modules/network/private-service-access/` - Private Service Access (SQL/Redis)
- `modules/network/vpn/` - Cloud VPN (HA/BGP)
- `modules/network/interconnect/` - Cloud Interconnect
- `modules/network/internal-lb/` - Internal Load Balancer
- `modules/network/nat/` - Cloud NAT
- `modules/network/packet-mirroring/` - Packet Mirroring
- `modules/network/shared-vpc-service/` - Shared VPC Service Attachment
- `modules/network/vpc-flow-logs/` - VPC Flow Logs
- `modules/network/vpc-sc/` - VPC Service Controls

#### **IAM & Security**
- `modules/iam/organization/` - Organization IAM
- `modules/iam/role/` - Custom IAM roles
- `modules/iam/identity_group/` - Group management
- `modules/iam/identity_group_memberships/` - Group memberships

- `modules/iam/service_account/` - Service Account management
- `modules/iam/workload_identity/` - Workload Identity Federation

#### **Governance**
- `modules/governance/billing/` - Budget monitoring
- `modules/governance/cloud-audit-logs/` - Audit logging
- `modules/governance/org-policy/` - Organization Policies
- `modules/governance/scc/` - Security Command Center
- `modules/governance/kms/` - Key Management Service
- `modules/governance/tags/` - Resource Tags

#### **Orchestration**
- `modules/host/` - Compatibility wrapper used by the app root
- `modules/stages/` - Landing Zone stages (Bootstrap, Org, Projects, Network Hub, Workload)

---

## Available Commands

Run `make help` to see all commands. Most commonly used:

### **Development**
```bash
make install           # Install all required tools
make fmt               # Format all Terraform files
make validate-all      # Validate all supported roots (requires provider access)
make lint              # Run TFLint (requires a working local TFLint plugin install)
make security          # Run security scans
make ci                # Run complete CI pipeline
```

### **Environment Operations**
```bash
make init-organization               # Initialize the organization root
make plan-organization               # Plan organization changes
make init-apps APP_ENV=dev           # Initialize the apps root for a workspace
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars
make apply-apps APP_ENV=prod APP_VARS=examples/prod.tfvars
```

### **Documentation & Quality**
```bash
make docs              # Generate module documentation
make docs-check        # Verify documentation is current
make pre-commit-run    # Run all pre-commit hooks
make clean             # Clean temporary files
```

See the **[Makefile](Makefile)** for the complete list of supported commands.

---

## Security & Quality

### **Automated Security Scanning**
- **Local `make security`**: TFSec and Checkov
- **GitHub `security-scan.yml`**: TFSec, Checkov, Trivy, and Gitleaks

### **Quality Tools**
- **TFLint** - Terraform linting
- **terraform validate** - Syntax validation
- **terraform fmt** - Code formatting
- **pre-commit** - Automated formatting and repository checks

Run security scans:
```bash
make security              # Run all security scans
make security-report       # Generate detailed reports
```

---

## CI/CD Pipeline

### **GitHub Actions Workflows**

| Workflow | Trigger | Purpose |
|:---|:---|:---|
| **[terraform-plan.yml](.github/workflows/terraform-plan.yml)** | Pull Request | Format, docs, validation, lint, security |
| **[terraform-apply.yml](.github/workflows/terraform-apply.yml)** | Tags (`organization/v*`, `apps/*/v*`) | Verify Terraform Cloud run and publish release metadata |
| **[security-scan.yml](.github/workflows/security-scan.yml)** | Push, Weekly | Comprehensive security scanning |
| **[documentation.yml](.github/workflows/documentation.yml)** | Module changes | Auto-generate documentation |

### **Deployment**

Publish release metadata using git tags after the corresponding Terraform Cloud run has completed successfully:

```bash
# Organization control plane
git tag -a organization/v1.0.0 -m "Release organization v1.0.0"
git push origin organization/v1.0.0

# Application environment
git tag -a apps/prod/v1.0.0 -m "Release apps prod v1.0.0"
git push origin apps/prod/v1.0.0
```

---

## Module Documentation

Each module includes auto-generated documentation using `terraform-docs`:

- Input variables with descriptions and validation
- Output values
- Resource definitions
- Usage examples

Generate documentation:
```bash
make docs              # Generate docs for all modules
make docs-check        # Verify docs are up to date
```

---

## Troubleshooting

Having issues? Check these resources:

1. **[Troubleshooting Guide](docs/guides/TROUBLESHOOTING.md)** - Common issues and solutions
2. **[Quick Start Guide](docs/guides/QUICK_START.md)** - Setup instructions
3. **[Documentation Index](docs/INDEX.md)** - All documentation
4. **Run diagnostics**: `make fmt-check && make docs-check && make security`

---

## Project Status

| Category | Status |
|:---|:---:|
| **Deployable Roots** | 2 |
| **CI/CD Automation** | 4 Workflows |
| **Security Scanning** | 4 Tools |
| **Execution Model** | Terraform Cloud |
| **Documentation** | Current |
| **Production Ready** | **Target State** |

---

## External Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [GCP Best Practices](https://cloud.google.com/docs/enterprise/best-practices-for-enterprise-organizations)
- [TFLint Rules](https://github.com/terraform-linters/tflint/tree/master/docs/rules)
- [TFSec Checks](https://aquasecurity.github.io/tfsec/)

---

## Quick Reference

### **I want to...**

**Get started quickly**
→ [Quick Start Guide](docs/guides/QUICK_START.md)

**Understand the architecture**
→ [System Architecture](docs/architecture/ARCHITECTURE.md)

**See all documentation**
→ [Documentation Index](docs/INDEX.md)

**Fix an issue**
→ [Troubleshooting Guide](docs/guides/TROUBLESHOOTING.md)

**Run commands**
→ `make help` or see [Makefile](Makefile)

**Plan organization changes**
→ `make plan-organization`

**Plan app changes**
→ `make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars`

**Run quality checks**
→ `make ci`
