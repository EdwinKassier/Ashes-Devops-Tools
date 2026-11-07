# FinOps Deep-Dive — Cost of the Defaults

**Date:** 2026-11-04
**Scope:** The recurring monthly cost of standing up the landing-zone roots with **default variable values**, before any workload. AWS + GCP. This is the cost-of-defaults follow-up to the 2026-11-04 best-practice audit.
**Pricing basis:** Approximate AWS/GCP on-demand list prices, region `eu-west-2` (London), `az_count = 2` (the shipped default), USD. Figures exclude data processing, egress, and per-request charges, which scale with traffic. Fixed hourly items (firewall, NAT, endpoints, transit gateway, resolver) are deterministic and reliable. Usage-based security services are given as ranges because they scale with account count, log volume, and activity. Verify against the AWS and GCP calculators before acting.

---

## 1. Verdict

**The repo is cost-aware, but the default footprint is a production-grade, always-on inspection and security stack whose idle baseline exceeds its own default budget.** Both clouds ship real budgets, AWS adds Cost Anomaly Detection, cost-allocation tags are activated, the expensive services are gated behind flags, and the docs carry an honest cost table with right-sizing guidance. That is better than most landing zones. The problem is the default itself: applying the roots as shipped produces an idle bill of roughly **USD 1,400 to 1,900 per month on AWS plus USD 100 to 160 on GCP, before a single workload runs**. The AWS network hub alone (about USD 1,200) is already above the shipped USD 1,000 default budget, so the budget alert fires on day one with nothing deployed. There is also no cheap on-ramp: you cannot run one small AWS workload without first paying for the full hub.

**Net:** good instrumentation, prod-sized defaults, and a budget calibrated below reality. The fix is a minimal non-prod preset and a realistic default budget, not more tooling.

---

## 2. Estimated idle baseline (default apply, no workload)

### AWS network hub (fixed, deterministic) — the big ticket

| Item | Quantity (default) | Approx USD/month | Source |
|---|---|---|---|
| Network Firewall endpoints | 2 (one per AZ) | ~577 | `modules/aws/stages/network-hub/variables.tf:140`; firewall per-subnet `modules/aws/network/network-firewall/main.tf:72` |
| Route 53 Resolver endpoints | 4 ENIs (inbound 2 + outbound 2) | ~365 | `modules/aws/network/route53-resolver/main.tf:15-39` |
| VPC interface endpoints | 14 ENIs (7 services x 2 AZ) | ~102 | `modules/aws/network/vpc-endpoints/variables.tf:34`; subnets `stages/network-hub/main.tf:220` |
| Transit Gateway attachments | 2 (inspection + egress) | ~73 | `modules/aws/stages/network-hub/main.tf:173-201` |
| NAT Gateways | 2 (one per AZ) | ~70 | `modules/aws/stages/network-hub/main.tf:123-145` |
| IPAM + flow logs + misc | baseline | ~15 | `stages/network-hub/main.tf:65`; `modules/aws/network/vpc/main.tf:80` |
| **Network subtotal** | | **~1,200** | |

### AWS security baseline (org-wide, ~8 accounts, single region) — usage-scaling

| Service | Default | Approx USD/month (idle) | Note |
|---|---|---|---|
| AWS Config (record all resource types) | on, org-wide | 50 to 150 | `config-org/variables.tf:68`; scales badly with resource count |
| Security Lake | on | 50 to 200 | `stages/security/variables.tf:205`; ingestion + S3 + Glue |
| GuardDuty (full suite + EBS malware) | on, all accounts | 30 to 100 | `guardduty-org/main.tf:44-57` |
| Macie | on, org-wide | 20 to 100 | `stages/security/variables.tf:192` |
| Security Hub (3 standards) | on | 15 to 50 | `securityhub-org/main.tf:32-34` |
| Inspector (EC2/ECR/Lambda) | on | 0 to 10 | near zero until workloads exist |
| KMS (3 CMKs) + CloudTrail storage | on | 10 to 30 | |
| **Security subtotal** | | **~180 to 650** | midpoint ~300 |

**AWS idle total: ~USD 1,400 to 1,900 per month**, growing with each account, region, and workload.

### GCP baseline

| Item | Quantity (default) | Approx USD/month | Source |
|---|---|---|---|
| Cloud NAT gateways | 2 (hub + DNS-anchor VPC) | ~64 | `modules/gcp/stages/host/main.tf:170-191`, instantiated twice |
| PSC endpoints | 2 | ~15 | `host/main.tf:206-215` |
| Cloud Armor policies | 2 | ~14 | `host/main.tf:379-390` |
| Audit logs (GCS + BigQuery), KMS (5 keys), Cloud DNS | baseline | 10 to 40 | `stages/organization/main.tf:51-107` |
| **GCP total** | | **~100 to 160** | SCC is notification-only, so no paid-tier cost |

**Combined idle baseline: ~USD 1,600 to 2,100 per month, before any workload.**

---

## 3. Findings

### HIGH

**F1 — The idle baseline exceeds the shipped default budget, so the budget alert is meaningless on day one.**
The default AWS budget is a single org-wide USD 1,000 limit alerting at 80% actual spend (`cost-governance/variables.tf:22-28`). The network hub alone is about USD 1,200 per month idle, and the full AWS baseline is about USD 1,500. So the moment the landing zone is applied, spend is already over budget with zero workloads. An alert that fires immediately and permanently trains operators to ignore it. The GCP budget (also USD 1,000, `envs/gcp/organization/variables.tf:184`) is closer to its baseline but still low. Fix: set the default budgets to reflect the real baseline (AWS nearer USD 2,500 to 3,000 with headroom), and add forecasted alerts, not only actual-spend.

**F2 — There is no cheap on-ramp: the full network hub is a sunk prerequisite before workload one.**
`envs/aws/workload` consumes the network cross-root contract (TGW id, IPAM pool), and the runbook order forces org then security then network then workload. So a single small AWS workload requires the whole hub first: 2 firewall endpoints, 4 resolver ENIs, 14 interface endpoints, a transit gateway, and 2 NAT gateways, about USD 1,200 per month floor. For a dev, sandbox, or small-team environment this is large, unavoidable waste. Right-sizing guidance exists in the docs, but it requires overriding many flags per environment. Fix: ship a documented minimal non-prod preset (`az_count = 1`, firewall off, single NAT, fewer endpoints) and a standalone-VPC workload path that does not require the hub.

### MEDIUM

**F3 — You pay for two NAT gateways but use one.**
`aws_nat_gateway.this` is created per AZ (2), but the single shared private route table routes all egress through `NAT[0]` (`modules/aws/stages/network-hub/main.tf:123-160`). So the second NAT (about USD 35 per month) carries no traffic and gives no egress failover, because the route table does not fail over either. This is the worst of both: redundant cost without redundant availability. Fix: either add per-AZ private route tables for real high availability, or drop to a single NAT and save about USD 35 per month.

**F4 — GCP host defaults leak into the DNS-anchor VPC.**
`modules/gcp/stages/network-hub` calls the `host` stage twice (hub and DNS-anchor) without overriding the host billable defaults, so the DNS-anchor VPC gets its own Cloud Armor policy, PSC endpoint, Cloud NAT, and Cloud Router that it has no use for (`stages/network-hub/main.tf:104-118`). That duplicates those line items for no benefit, about USD 40 per month wasted. Fix: pass minimal feature flags for the DNS-anchor host call (`enable_cloud_armor = false`, `enable_private_service_connect = false`, Cloud NAT off).

**F5 — The maximum-cost security set is the default, including for non-prod.**
Security Lake, Config record-all, GuardDuty full suite plus EBS malware, Macie, and Inspector are all auto-enrolled across all accounts (`stages/security/variables.tf:192-214`). The docs honestly flag the top four and give right-sizing guidance, which is a real strength, but the shipped default is the most expensive posture. Config record-all and Security Lake in particular scale badly as resources and logs grow. Fix: default non-prod to a reduced set and keep the full set for prod via environment tfvars.

**F6 — Budget and anomaly alerts can go to nobody.**
The budget and Cost Anomaly Detection subscriptions accept an email and SNS target that may be empty by default (`cost-governance`). If unset, the alert fires into the void. A budget that notifies no one is not a control. Fix: make at least one notification target mandatory with a validation, or document it as a required input before first apply.

### LOW

**F7 — Single org-wide, actual-spend AWS budget.**
The default is one org-wide budget on actual spend. Best practice is per-account or per-environment budgets plus forecasted alerts (which warn before the overspend) and tiered thresholds (50, 80, 100 percent). One org budget cannot localize which account is burning. GCP already uses a 50% threshold, which is better. Fix: ship per-environment budgets with forecasted alerts.

**F8 — AWS VPC flow logs are unsampled.**
AWS flow logs capture ALL traffic to S3 with no sampling (`modules/aws/network/vpc/main.tf:80`), while GCP samples at 0.5 (`stages/network-hub/main.tf:35`). On the inspection and egress VPCs at scale, full-fidelity flow logs are a real S3 and ingestion cost. Fix: expose a sampling or aggregation-interval control, or document the trade-off.

---

## 4. What is genuinely strong (credit where due)

- **Both clouds ship real default budgets**, AWS adds Cost Anomaly Detection (USD 100 threshold) and activates cost-allocation tags in Cost Explorer. Most landing zones ship no cost guardrails at all. This one is cost-aware by design.
- **The expensive services are all gated** behind `enable_*` flags, and `docs/architecture/aws-landing-zone.md` carries an explicit cost table plus right-sizing guidance. The cost is disclosed, not hidden.
- **Correctly cheap where it counts.** CloudTrail records management events only, with no data events or Insights (the classic CloudTrail cost trap, avoided). GCP SCC is notification-only, not a paid tier. ACM Private CA, Firewall Manager, Detective, Secrets baseline, VPN, CDN, and API Gateway are all correctly off by default. These are the exact defaults that quietly cost thousands elsewhere.
- **IPv4-only by default** avoids dual-stack surprises. **Tag-policy enforces cost-allocation tags**, so showback and chargeback are possible.

---

## 5. Recommended priorities

1. Recalibrate the default budgets to the real baseline and add forecasted alerts (F1). This is a one-line change with high value.
2. Ship a minimal non-prod tfvars preset and a standalone-VPC workload path, so small environments are not forced into the full hub (F2).
3. Fix the dual-NAT waste and the GCP DNS-anchor VPC leak (F3, F4). Both are small, safe edits.
4. Default non-prod to a reduced security set; keep full posture for prod (F5).
5. Make a budget notification target mandatory (F6).

---

## 6. Caveats

- Figures are approximate list prices for `eu-west-2` at `az_count = 2`, excluding data processing and egress. Actual cost depends on region, account count, log volume, and traffic. The fixed network items are reliable; the security services are ranges that grow with activity.
- No live billing data was available. This is a static estimate from the default variable values, not a measured bill. A real apply plus one month of Cost Explorer or GCP billing export would replace these estimates with facts, which is the same proof gap noted as M0 in the main audit.
