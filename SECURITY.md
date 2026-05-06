# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email **security@ashesproject.com** with the details below. We will acknowledge within 48 hours and keep you informed of progress.

### What to Include

- Description of the vulnerability and affected component
- Steps to reproduce (proof of concept if possible)
- Potential impact and severity assessment
- Any suggested mitigations

### Disclosure Timeline

| Severity | CVSS Score | Target Fix | Disclosure |
|----------|------------|-----------|------------|
| Critical | 9.0–10.0 | 7 days | Coordinated after patch |
| High | 7.0–8.9 | 14 days | Coordinated after patch |
| Medium | 4.0–6.9 | 30 days | Next scheduled release |
| Low | < 4.0 | Next release | Next scheduled release |

We will coordinate public disclosure with you. If you prefer to remain anonymous, let us know.

---

## Security Architecture

This landing zone implements defense-in-depth across every layer:

### Identity & Access
- **Workload Identity Federation** — keyless authentication for CI/CD (no long-lived service account keys)
- **IAM least privilege** — all module roles validated against a blocklist of primitive roles (`roles/owner`, `roles/editor`, `roles/viewer`)
- **Separate service accounts** per stage (bootstrap, network, workload)

### Data Protection
- **CMEK (Customer-Managed Encryption Keys)** via Cloud KMS — all storage encrypted at rest
- **Key rotation enforced** — rotation period validated between 1–90 days at plan time
- **Uniform bucket-level access** — no per-object ACLs on Cloud Storage

### Network Security
- **VPC Service Controls** — data perimeter around sensitive projects
- **Private Service Access** — RFC 1918 connectivity to Google APIs (no public egress for managed services)
- **Cloud Armor** — WAF with OWASP rule sets for internet-facing workloads
- **VPC Flow Logs** — full network telemetry retained in Cloud Storage

### Audit & Compliance
- **Cloud Audit Logs** — Data Access logs enabled for all services, 730-day retention
- **Security Command Center** — notifications for HIGH and CRITICAL findings
- **Org Policies** — domain-restricted sharing, uniform bucket access, disable SA key creation

### CI/CD Security
- **All GitHub Actions SHA-pinned** — no mutable tag references
- **Branch protection** — required reviews and status checks before merge
- **Secret scanning** — Gitleaks runs on every PR
- **Static analysis** — TFSec, Checkov, and Trivy on every PR and nightly

---

## Supported Versions

| Component | Supported Until |
|-----------|----------------|
| `organization/v1.x` | Active |
| `apps/*/v1.x` | Active |

---

## Security Scanning

This repo runs the following automated security tools:

| Tool | Scope | Trigger |
|------|-------|---------|
| [TFSec](https://aquasecurity.github.io/tfsec/) | Terraform static analysis | Every PR + nightly |
| [Checkov](https://www.checkov.io/) | Infrastructure policy compliance | Every PR + nightly |
| [Trivy](https://aquasecurity.github.io/trivy/) | Container + IaC scanning | Every PR + nightly |
| [Gitleaks](https://gitleaks.io/) | Secret detection in git history | Every PR |

SARIF results are uploaded to GitHub Security tab for all scans.

---

## Contact

- Security issues: security@ashesproject.com
- General inquiries: edwinkassier@gmail.com
