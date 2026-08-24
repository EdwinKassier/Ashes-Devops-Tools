# Landing-Zone Best-Practice Conformance (2026 review)

This is the cross-cloud record of how closely each landing zone adheres to the
**latest published best practice** (reviewed 2026-08), and where it lags. It is
written to treat both clouds identically — same structure, same honesty — so you
can judge them side by side. It complements the per-cloud conformance tables in
[`aws-landing-zone.md`](aws-landing-zone.md) and
[`gcp-landing-zone.md`](gcp-landing-zone.md); the actionable gaps are tracked
with IDs in [`known-gaps.md`](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review).

## Verdict

| Cloud | Adherence | One-line |
|:------|:----------|:---------|
| **AWS** | **Very close** to the latest AWS SRA | Has the newest Organizations controls (RCP, declarative policies, centralized root access), Security Hub CENTRAL config, Access Analyzer unused-access, modern GuardDuty, and every June-2026 SRA checklist service. Gaps are at the margins. |
| **GCP** | **Strong** on the enterprise-foundations fabric | Keyless WIF, org-wide Data-Access logging, CIS-aligned org policy, CMEK, Shared-VPC hub-and-spoke, VPC-SC scaffolding. Lags in a handful of recent-GA areas (managed/custom org-policy constraints, network firewall policies, IAM deny, SCC posture). |

Neither cloud has a correctness bug in this review; the gaps are modernization
items against 2024–2026 guidance. Most GCP gaps are cheap opt-in/default-off
additions; the heavier items on both sides need a real apply and are documented
rather than rushed.

## Reference baselines

| Cloud | Frameworks used for this review |
|:------|:--------------------------------|
| AWS | [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html) (incl. the Aug-2025 RCP/declarative and Nov-2025 root-access updates, and the June-2026 doc-history revision); AWS Well-Architected Security Pillar; AWS Backup 2025 resilience guidance. |
| GCP | [Google Cloud enterprise foundations blueprint](https://docs.cloud.google.com/architecture/blueprints/security-foundations) (last reviewed 2025-05-15; `terraform-example-foundation` v5.0.0, 2026-07-01); [Cloud Foundation Fabric / FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric); [CIS GCP Foundation Benchmark v5.0.0](https://www.cisecurity.org/benchmark/google_cloud_computing_platform) (2026-05-09). |

## What each cloud already gets right

**AWS** — RCP data-perimeter + `DECLARATIVE_POLICY_EC2` + all five Organizations policy types default-on; centralized root-access management (`RootCredentialsManagement` + `RootSessions`); Security Hub **CENTRAL** configuration; IAM Access Analyzer **external + unused-access** analyzers; GuardDuty with the full modern feature set (S3 data events, EKS audit, RDS login, Lambda network, Runtime Monitoring) + Extended Threat Detection; Compliance-mode Vault Lock (WORM) backups with restore testing; CloudTrail Lake correctly *not* adopted (SRA-deprecated Dec-2025).

**GCP** — keyless automation identity (GitHub + TFC WIF; SA key creation **and** upload denied org-wide); org-wide Data-Access audit logging (`ADMIN_READ`/`DATA_READ`/`DATA_WRITE` on all services, `include_children` sink); CIS-aligned org-policy set (deny external IP, no default-SA grants, Shielded VM, UBLA, restrict SQL public IP, domain-restricted sharing) with a stricter prod-folder subset; CMEK on all sensitive stores with 90-day rotation; hierarchical firewall using the modern `firewall_policy` construct; VPC-SC + Access Context Manager fully modeled.

## Gap register

Severity H/M/L. Class: **DOC** (fixed in this review) · **CONFIG** (default-off opt-in, safe to add) · **BEHAVIOR** (needs a real apply / architectural change — documented).

### AWS

| ID | Gap | Sev | Class |
|:---|:----|:----|:------|
| [A5](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | Single-region backups — no cross-region `copy_actions` or air-gapped destination vault | M | BEHAVIOR |
| [A6](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | June-2026 SRA makes CloudWatch Unified Data Store the analytics *primary*; zone keeps S3 WORM as immutable sink, CloudWatch out-of-band | M | DOC / BEHAVIOR |
| [A7](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | Config conformance packs are an empty bring-your-own hook (no bundled pack) | M | DOC / CONFIG |
| — | Security Hub CIS standard was pinned to v1.4.0 | L | **CONFIG — fixed** (now CIS v3.0.0) |
| — | GuardDuty S3 Malware Protection managed out-of-band | L | DOC — disclosed |

### GCP

| ID | Gap | Sev | Class |
|:---|:----|:----|:------|
| [G6](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | No Organization Policy custom or `*.managed.*` constraints (module supports custom; stage wires none) | H | CONFIG |
| [G7](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | Host firewall uses legacy `google_compute_firewall` rules, not network firewall policies with IAM-governed tags | H | BEHAVIOR |
| [G8](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | Audit-log bucket has no locked (WORM) retention | M | CONFIG |
| [G9](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | No IAM Deny policies as a coarse permission backstop | M | CONFIG |
| [G10](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | SCC notification-only — no posture service / tier (target Premium; Enterprise sunsets 2027-05-21) | M | BEHAVIOR |
| [G11](../known-gaps.md#modernization--latest-best-practice-gaps-2026-review) | VPC-SC perimeters enforce-first, no dry-run default | L–M | CONFIG |
| — | No KMS Autokey; CMEK defaults to SOFTWARE protection | L | CONFIG |
| — | Flat folder tree (no prod/nonprod grouping layer) | L | BEHAVIOR |

Already tracked separately (not repeated here): AWS **A1/A3/A4**, GCP **G3/G4/G5** and the break-glass note — see [`known-gaps.md`](../known-gaps.md).

## How to read the asymmetry honestly

The AWS SRA prescribes many discrete org-wide services, so "adherence" there is
largely *have you wired each one* — and this repo has. Google's foundations
consolidate more into org policy + IAM + a smaller service set, so GCP adherence
is more about *modern construct choice* (managed constraints, network firewall
policies, IAM deny, SCC posture) than service count. The two clouds are close to
parity in **rigor**; they differ in **shape**, which is expected.

## See also

- [GCP Landing Zone](gcp-landing-zone.md) · [AWS Landing Zone](aws-landing-zone.md) — per-cloud conformance tables.
- [Known Gaps](../known-gaps.md) — the actionable tracker (IDs above).
- [Cross-Cloud Comparison](cross-cloud-comparison.md) — where each capability lives per cloud.
