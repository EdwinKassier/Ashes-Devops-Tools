# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities via the repository's **Security** tab → **"Report a vulnerability"**
(GitHub private vulnerability reporting). **This is the only guaranteed channel** and
reaches the maintainers directly and confidentially. We aim to acknowledge within 48
hours and keep you informed of progress.

> **Email backstop not yet configured.** A role-based alias (`security@…`) is intended
> as a fallback but is **not live yet** — do not rely on email until this notice is
> removed. Until then, use GitHub private vulnerability reporting above. Maintainers:
> configure a real alias and replace this notice before any public release.

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

- **CMEK (Customer-Managed Encryption Keys)** via Cloud KMS — available across storage primitives. Storage is always encrypted at rest; buckets default to Google-managed keys (GMEK) and accept a CMEK via `kms_key_name`, with the composing stages wiring a CMK for regulated data. Require a CMEK at the module boundary for compliance environments.
- **Key rotation enforced** — rotation period validated between 1–365 days at plan time
- **Uniform bucket-level access** — no per-object ACLs on Cloud Storage
- **Opt-in WORM retention** — audit-log buckets support a locked retention policy via `enable_bucket_lock` (default off; the org-level Cloud Logging sink is the authoritative tamper-evident copy)

### Network Security

- **VPC Service Controls** — data perimeter around sensitive projects. **Ships in dry-run mode by default** (audit-only; it logs would-be violations but does not block them). Promote to enforced per environment once ingress/egress rules are validated — see [known-gaps.md](docs/known-gaps.md).
- **Private Service Access** — RFC 1918 connectivity to Google APIs (no public egress for managed services)
- **Cloud Armor** — WAF with OWASP rule sets for internet-facing workloads
- **VPC Flow Logs** — full network telemetry retained in Cloud Storage

### Audit & Compliance

- **Cloud Audit Logs** — Data Access logs enabled for all services; retention configurable via `audit_log_retention_days` (default 365 days; increase for PCI-DSS/HIPAA/FedRAMP)
- **Security Command Center** — notifications for HIGH and CRITICAL findings
- **Org Policies** — domain-restricted sharing, uniform bucket access, disable SA key creation

### CI/CD Security

- **All GitHub Actions SHA-pinned** — no mutable tag references
- **Branch protection** — required reviews and status checks before merge
- **Secret scanning** — Gitleaks runs on push to `main`/`develop` and weekly (not on every PR; the PR gate runs TFSec + Checkov only)
- **Static analysis** — TFSec and Checkov on every PR; TFSec, Checkov, and Trivy again on push to `main`/`develop` and weekly

---

## Supported Versions

This is a **pre-1.0 boilerplate with no tagged releases yet** (`git tag` is currently
empty). Consume it by pinning to a specific commit SHA; `main` is the supported line and
receives the security fixes described above.

A tag-based release and support model (`gcp-organization/vX.Y.Z`, `gcp-workload/<env>/vX.Y.Z`)
is wired in `terraform-apply.yml` and the CHANGELOG for when the first release is cut. The
table below becomes authoritative at that point:

| Component | Supported |
|-----------|-----------|
| `main` (untagged) | Active — pin to a commit SHA |
| `gcp-organization/v1.x` | Not yet released |
| `gcp-workload/*/v1.x` | Not yet released |

---

## Security Scanning

This repo runs the following automated security tools:

| Tool | Scope | Trigger |
|------|-------|---------|
| [TFSec](https://aquasecurity.github.io/tfsec/) | Terraform static analysis | Every PR + push to main/develop + weekly |
| [Checkov](https://www.checkov.io/) | Infrastructure policy compliance | Every PR + push to main/develop + weekly |
| [Trivy](https://aquasecurity.github.io/trivy/) | Container + IaC scanning | Push to main/develop + weekly |
| [Gitleaks](https://gitleaks.io/) | Secret detection in git history | Push to main/develop + weekly |

SARIF results are uploaded to GitHub Security tab for all scans.

---

## Contact

- Security issues: repository **Security** tab → **"Report a vulnerability"** (the only
  guaranteed channel). A `security@…` email backstop is planned but **not yet configured**
  — see the notice under "Reporting a Vulnerability" above.
- General inquiries: open a [GitHub Discussion](../../discussions) or non-security issue
  on this repository
