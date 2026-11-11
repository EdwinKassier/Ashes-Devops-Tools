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
- **Opt-in WORM retention**: `gcp.enable_audit_bucket_lock` locks the audit bucket's retention policy (irreversible). Without it, the bucket is versioned and access-controlled but not immutable. Regulated environments require it.

### Network Security

- **VPC Service Controls** — data perimeter around sensitive projects. **Ships in dry-run mode by default** (audit-only; it logs would-be violations but does not block them). Promote to enforced per environment once ingress/egress rules are validated — see [known-gaps.md](docs/known-gaps.md).
- **Private Service Access** — RFC 1918 connectivity to Google APIs (no public egress for managed services)
- **Cloud Armor** — WAF with OWASP rule sets for internet-facing workloads
- **VPC Flow Logs**: on every subnet, exported to a CMEK BigQuery dataset per environment (default 10% sampling, 30-day retention). Raise `log_config_flow_sampling` and `vpc_flow_logs_retention_days` for regulated environments.

### Audit & Compliance

- **Cloud Audit Logs**: Data Access logs on for all services. The audit bucket retention is the organization stage variable `audit_log_retention_days` (default 365 days). The landing zone does not enforce framework minimums. In the gcp-organization root the retention is fixed at 365 days: the root does not pass `audit_log_retention_days`, so only a direct caller of the stage can change it. Exposing it through `config/landing-zone.yaml` is planned (WS4 Task 5). Until then, root users who need a longer period for PCI DSS, HIPAA or FedRAMP must call the stage directly.
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

- Security issues: repository **Security** tab → **"Report a vulnerability"** (the only
  guaranteed channel). A `security@…` email backstop is planned but **not yet configured**
  — see the notice under "Reporting a Vulnerability" above.
- General inquiries: open a [GitHub Discussion](../../discussions) or non-security issue
  on this repository
