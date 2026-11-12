# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities through the repository's **Security** tab, **Report a vulnerability**
(GitHub private vulnerability reporting). It is the only channel; there is no security
email address. It reaches the maintainers directly and confidentially. We aim to
acknowledge within 48 hours and keep you informed of progress.

**Maintainers:** this channel works only while the repository setting is on (Settings,
Code security, Private vulnerability reporting). A repository admin must switch it on.
`make security-contact-live` checks the setting (read-only, needs `gh` access).

**Forks:** private vulnerability reporting is a per-repository setting. Switch it on in your
fork, or replace this section with your own channel.

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

## Operators: Regulatory Notification

If you run this landing zone and an incident involves personal data, health data, card data or a regulated service, notification deadlines can start before the investigation ends. See the [regulatory notification runbook](docs/runbooks/regulatory-notification.md). It is a working summary, not legal advice.

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
- **Opt-in WORM retention**: `gcp.enable_audit_bucket_lock` locks the audit bucket's retention policy (irreversible). Without it, the bucket is versioned and access-controlled but not immutable. Required for regulated environments (`compliance_class: regulated`), together with a separate logging project (`gcp.logging_project_id`): the `gcp-organization` plan fails without both unless `gcp.audit_store_waived` is true.

### Network Security

- **VPC Service Controls** — data perimeter around sensitive projects. **Ships in dry-run mode by default** (audit-only; it logs would-be violations but does not block them). Promote to enforced per environment once ingress/egress rules are validated — see [known-gaps.md](docs/known-gaps.md).
- **Private Service Access** — RFC 1918 connectivity to Google APIs (no public egress for managed services)
- **Cloud Armor** — WAF with OWASP rule sets for internet-facing workloads
- **VPC Flow Logs**: on every subnet, exported to a CMEK BigQuery dataset per environment (default 10% sampling, 30-day retention). Raise `log_config_flow_sampling` and `vpc_flow_logs_retention_days` for regulated environments.

### Audit & Compliance

- **Cloud Audit Logs**: Data Access logs on for all services. The audit bucket retention is `compliance.audit_log_retention_days` in `config/landing-zone.yaml` (or the `gcp-organization` root variable `audit_log_retention_days`), default 365 days. When `compliance.frameworks` lists `pci_dss`, `hipaa` or `fedramp_moderate`, the plan fails for a retention below that framework's floor (365, 2190 or 913 days). The floors are minimums; they do not prove that a framework is met. With the WORM lock on, the retention must be at least 365 days and can only be increased.
- **AWS log archive**: S3 Object Lock in COMPLIANCE mode by default. The default retention is the same `compliance.audit_log_retention_days` (or the `aws-security` override `aws_overrides.log_archive_retention_days`), default 365 days, with the same framework floors. It applies to new objects only; objects already written keep their retain-until date. With `compliance.frameworks` set, the plan refuses `log_archive_object_lock_mode = "GOVERNANCE"`.
- **Security Command Center**: a Pub/Sub notification of every ACTIVE finding (CMEK topic). The SCC tier is activated outside Terraform.
- **Org Policies** — domain-restricted sharing, uniform bucket access, disable SA key creation

### CI/CD Security

- **All GitHub Actions SHA-pinned** — no mutable tag references
- **Branch protection**: not codified in this repository. Required reviews and status checks are GitHub repository settings that the maintainers configure (see `docs/guides/BRANCH_PROTECTION.md` and `docs/runbooks/promotion.md`). Verify them in the repository settings.
- **Secret scanning** — Gitleaks runs on push to `main`/`develop` and weekly (not on every PR; the PR gate runs Trivy + Checkov)
- **Static analysis** — Trivy (config) and Checkov on every PR, and again on push to `main`/`develop` and weekly (TFSec is EOL and folded into Trivy)

---

## Supported Versions

This is a **pre-1.0 boilerplate**. One release exists: `v0.1.0` (2026-11-08), tagged by hand.
Consume it by pinning to that tag or to a specific commit SHA. `main` is the supported line
and receives the security fixes described above.

A tag-based release and support model (`gcp-organization/vX.Y.Z`, `gcp-workload/<env>/vX.Y.Z`)
is wired in `terraform-apply.yml` and the CHANGELOG. No such component tags exist yet. The
table below becomes authoritative when they do:

| Component | Supported |
|-----------|-----------|
| `main` | Active: pin to a tag or commit SHA |
| `v0.1.0` | Pin target only; security fixes land on `main` |
| `gcp-organization/v1.x` | Not yet released |
| `gcp-workload/*/v1.x` | Not yet released |

---

## Security Scanning

This repo runs the following automated security tools:

| Tool | Scope | Trigger |
|------|-------|---------|
| [Trivy](https://aquasecurity.github.io/trivy/) (`trivy config`) | Terraform static analysis (replaces the end-of-life TFSec) | Every PR + push to main/develop + weekly |
| [Checkov](https://www.checkov.io/) | Infrastructure policy compliance | Every PR + push to main/develop + weekly |
| [Trivy](https://aquasecurity.github.io/trivy/) (filesystem) | Dependency + IaC vulnerability scanning | Push to main/develop + weekly |
| [Gitleaks](https://gitleaks.io/) | Secret detection in git history | Push to main/develop + weekly |

SARIF results are uploaded to GitHub Security tab for all scans.

---

## Contact

- Security issues: the **Report a vulnerability** button above (no email address exists).
- General questions: open a non-security issue on this repository
