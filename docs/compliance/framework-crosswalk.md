# Framework crosswalk

Maps framework requirements to the controls in the
[control matrix](control-matrix.md). Use it to scope an assessment, not to
replace one. It is **design evidence only**: read the matrix's "Read this first"
before you show it to an auditor. Reviewed against the tree on 2026-11-12.

Versions cited: PCI DSS v4.0.1 (June 2024); HIPAA Security Rule, 45 CFR Part
164 Subpart C as in force (a proposed rule is not the law); DORA, Regulation
(EU) 2022/2554; NIST SP 800-53 Rev 5; FedRAMP Rev 5 Moderate baseline (as a
reference only); ISO/IEC 27001:2022 Annex A.

## How to read the tables

| Column | Meaning |
|:--|:--|
| Controls | Row IDs in the [control matrix](control-matrix.md). The matrix row has the full detail. |
| Code | A path in this repository. Every backticked path is checked by `scripts/check-matrix-paths.sh`. |
| Default | **On**: active on a default apply of the root. **Off**: opt-in. **Preset**: turned on by a `prod-*` preset. **Production scaffold**: written by `make init --profile production`. **Regulated**: on only for an environment with `compliance_class: regulated` ([regulated environments](../architecture/regulated-environments.md)). **Manual**: a console or admin step with no Terraform API. **Scaffold**: the plumbing is deployed, but the control does not act until you complete the code the matrix row names. **Customer**: the landing zone ships nothing for it. **Docs**: a runbook or register you adopt and run. |
| You still do | The customer share. A landing-zone control never covers your application, your people or your processes. |
| ID checked | **Yes**: the requirement ID was checked against the source named in [How the IDs were checked](#how-the-ids-were-checked). **No**: not checked; confirm it against the standard before you rely on it. |

## PCI DSS v4.0.1

| Req. | Requirement (short) | Controls | Code | Default | You still do | ID checked |
|:--|:--|:--|:--|:--|:--|:--|
| 1.2, 1.3 | Network security controls; restrict traffic to and from the cardholder data environment (CDE) | NET-01, NET-02, NET-05, NET-11 | `modules/gcp/stages/net-hub`, `modules/aws/stages/network-hub` | AWS: on; the egress gate fails the plan for a regulated estate, and for production on the production profile. GCP: partial; without the Secure Web Proxy (PREVIEW) a production environment runs on `production_egress_proxy_waiver` and Cloud NAT reaches any destination (a regulated environment's waiver may run 90 days at most). NET-11 Regulated | Define the CDE and segment it per environment; segmentation testing (11.4.5); a GCP egress allowlist until the proxy is proven | 1.3: Yes (1.3.1). 1.2: No |
| 1.4 | Controls between trusted and untrusted networks | NET-03, NET-07, GRD-08, DP-03 | `modules/gcp/network/cloud-armor`, `modules/aws/governance/organization-policy/policies/declarative-ec2.json` | NET-03 Preset; NET-07 and GRD-08 On (Workloads OU); DP-03 On | An edge (WAF) for each public app | Yes (1.4.4) |
| 2.2 | System components configured securely | GRD-01, GRD-08, GRD-10, VUL-06 | `modules/gcp/stages/organization/main.tf`, `modules/aws/governance/organization-policy/policies/declarative-ec2.json` | On | Hardening standards for your workloads | Yes (2.2.1, 2.2.6) |
| 3.5, 3.6, 3.7 | Protect stored account data; key management | DP-01, DP-02, DP-05, GRD-04 | `modules/gcp/governance/kms`, `modules/aws/data/kms-key` | Keys and rotation On; CMEK org policy Preset; Cloud SQL CMEK Regulated | PAN rendering, key custodians, crypto-period policy | 3.5: Yes (3.5.1). 3.7: Yes (3.7.4). 3.6: No |
| 4.2.1 | Strong cryptography in transit over open, public networks | DP-04, GRD-07 | `modules/aws/governance/organization-policy/policies/rcp-data-perimeter.json.tftpl`, `modules/gcp/network/app-ingress` | On (`gcp.restrictTLSVersion` in the production profile; CloudFront only with `enable_edge`) | TLS on every endpoint you add | Yes |
| 5.2, 5.3 | Anti-malware | DET-01 (GuardDuty, EBS malware protection) | `modules/aws/security/guardduty-org` | On; EBS malware scanning off in the `starter` profile | Anti-malware on GCP VMs and in containers | No |
| 6.3.3 | Critical security patches within one month of release | VUL-04, VUL-05 | `modules/aws/ops/systems-manager`, `modules/gcp/ops/os-config` | On (weekly install, `enable_patch_install`) | Patch evidence per instance; exceptions | Yes |
| 6.4.1, 6.4.2 | Protect public-facing web applications | NET-03, NET-09 | `modules/gcp/network/cloud-armor`, `modules/aws/security/edge-security` | NET-03 Preset (Regulated on GCP); NET-09 Off (on for a regulated AWS workload's public ALB, which also needs access logs) | Turn it on for every public app | 6.4.2: Yes. 6.4.1: No |
| 7.2 | Access defined and assigned by least privilege | IAM-02, IAM-05, IAM-06, IAM-14 | `modules/gcp/stages/bootstrap`, `modules/aws/iam/tfc-oidc-baseline`, `envs/aws/identity` | On | Access approval and periodic review | No |
| 8.4.2 | MFA for all access into the CDE | IAM-16 | `modules/aws/security/security-notifications` (alert only) | Alert On; enforcement Manual | Enforce MFA in IAM Identity Center or your identity provider, and in Google 2-Step Verification | Yes |
| 10.2 | Audit logs for all system components | LOG-01, LOG-06, LOG-07, LOG-13 | `modules/gcp/governance/cloud-audit-logs`, `modules/aws/security/cloudtrail-org` | On | Application logs | Yes (10.2.1) |
| 10.3.2 to 10.3.4 | Audit logs protected from change, backed up to a central store, change detection on logs | LOG-02, LOG-03, LOG-07, LOG-08, CHG-07 | `modules/aws/data/log-archive-bucket`, `modules/gcp/governance/cloud-audit-logs` | AWS Object Lock and log file validation On; GCP bucket lock Off, required for Regulated; CHG-07 Off until its secret is set | Keep the locks on; run `aws cloudtrail validate-logs` | 10.3.2: Yes. 10.3.3, 10.3.4: No |
| 10.4.1, 10.4.2 | Review logs and security events | LOG-05, LOG-09, LOG-10, LOG-14, DET-02 | `modules/gcp/monitoring/control-plane`, `modules/aws/security/security-notifications` | On (needs a notification address) | Staffed daily review and tickets | 10.4.2: Yes. 10.4.1: No |
| 10.5.1 | Keep audit logs 12 months, the latest 3 months immediately available | LOG-02, LOG-08 | `envs/gcp/organization`, `envs/aws/security` · `compliance.audit_log_retention_days` | On (365 days; the plan fails below 365 with `compliance.frameworks: [pci_dss]`). AWS objects stay in S3 Standard for 90 days, then move to Glacier | Keep the value at or above 365 | Yes |
| 10.7.2 | Detect, alert on and respond to failures of critical security controls | GRD-05, LOG-05, LOG-09 | `modules/aws/governance/organization-policy/policies/scp-deny-tamper.json.tftpl`, `modules/gcp/monitoring/control-plane` | On | Respond to the alerts and record it | No |
| 11.3 | Find and fix vulnerabilities; quarterly scans | VUL-01, VUL-02, VUL-06 | `modules/aws/security/org-security-service`, `modules/gcp/artifact-registry` | On (Inspector removed by the nonprod preset) | Quarterly external scans by an approved scanning vendor; remediation records | Yes (11.3.1) |
| 11.4 | Penetration testing | none | n/a | Customer | Yearly and after significant change, including segmentation tests | No |
| 11.5.1 | Detect and alert on intrusions | DET-01, NET-05 | `modules/aws/security/guardduty-org`, `modules/aws/network/network-firewall` | On | Respond to findings | Yes |
| 11.5.2 | Change-detection (file integrity monitoring) | DET-06 | none | Customer | Deploy a file integrity monitoring agent on CDE hosts | No |
| 12.8 | Manage third-party service providers | DP-09 | `envs/saas/main.tf`, `docs/compliance/third-parties.md` | DP-09 on when `saas.allowed_regions` or `aws.allowed_regions` is set; register: Docs | List providers and their responsibilities; keep it current | No |
| 12.10.1 | Incident response plan | DET-05 | `modules/aws/security/incident-response`, `docs/runbooks/regulatory-notification.md` | DET-05 Scaffold (the handler only logs); runbook: Docs | Approve the plan, test it yearly, add your acquirer and brand contacts; write the isolation handler if you rely on automated response | No |

## HIPAA Security Rule (45 CFR 164.308 to 164.316)

The labels Required and Addressable are the rule's own.

| Section | Standard or implementation specification | Controls | Default | You still do | ID checked |
|:--|:--|:--|:--|:--|:--|
| 164.308(a)(1)(ii)(A), (B) | Risk analysis; risk management (Required) | VUL-06, DET-02 (inputs only) | On | The risk analysis and the risk management plan | Yes |
| 164.308(a)(1)(ii)(D) | Information system activity review (Required) | LOG-05, LOG-09, LOG-10, LOG-14 | On | Review and document | Yes |
| 164.308(a)(3), (a)(4) | Workforce security; information access management | IAM-06, IAM-14, IAM-16 | On; MFA enforcement Manual | Joiner, mover and leaver process | Yes |
| 164.308(a)(5)(ii)(C) | Log-in monitoring (Addressable) | LOG-09 (CIS 4.6, console authentication failures), LOG-10 | On | Respond | Yes |
| 164.308(a)(6) | Security incident procedures | DET-05 | DET-05 Scaffold (the handler only logs); `docs/runbooks/regulatory-notification.md`: Docs | Response procedures and their records; breach risk assessment (164.402) | Yes |
| 164.308(a)(7)(ii)(A) | Data backup plan (Required) | BCK-01, BCK-03, BCK-04, BCK-07 | BCK-03 and BCK-04 On; BCK-01 copy Off, On in a production scaffold; BCK-07 Off, On for Regulated | Tag PHI resources `backup = true` | Yes |
| 164.308(a)(7)(ii)(B) | Disaster recovery plan (Required) | BCK-03 (`compliance.backup.dr_region`) | DR copy Off; `docs/runbooks/disaster-recovery.md`: Docs | Approve RTO and RPO; record measured values | Yes |
| 164.308(a)(7)(ii)(D) | Testing and revision procedures (Addressable) | BCK-02 | On; effective only with BCK-01 | Yearly DR exercise | Yes |
| 164.308(b)(1) | Business associate contracts | none in code | `docs/compliance/third-parties.md`: Docs | Sign BAAs (AWS, Google; Supabase and Vercel only on BAA-eligible plans) | Yes |
| 164.312(a)(1) | Access control | IAM-02, IAM-05, GRD-07 | On | | Yes |
| 164.312(a)(2)(iv) | Encryption and decryption (Addressable) | DP-01, DP-02, DP-03, GRD-04 | On; CMEK org policy Preset; Cloud SQL CMEK Regulated | Document the decision | Yes |
| 164.312(b) | Audit controls | LOG-01, LOG-07 | On | Application audit logs | Yes |
| 164.312(c)(1) | Integrity: protect ePHI from improper alteration or destruction | BCK-01, BCK-03, BCK-04, BCK-06, BCK-07 | BCK-03, BCK-04 and BCK-06 On; BCK-01 copy Off, On in a production scaffold; BCK-07 Off, On for Regulated | Versioning or Object Lock on the buckets that hold ePHI, and integrity checks in your application: the landing zone sets neither on workload data stores. Audit-log integrity (LOG-03, LOG-07, LOG-08) supports 164.312(b), not this standard | Yes |
| 164.312(d) | Person or entity authentication | IAM-01, IAM-05, IAM-16 | On; MFA enforcement Manual | Enforce MFA | Yes |
| 164.312(e)(1), (e)(2)(ii) | Transmission security; encryption (Addressable) | DP-04, GRD-07 | Partial. On: S3 TLS-only (GRD-07), Cloud SQL `ENCRYPTED_ONLY`, Aurora `rds.force_ssl = 1` by default; a regulated AWS workload needs an HTTPS ALB. Not covered: an AWS standard workload's internal ALB serves HTTP, and CloudFront VPC origin reaches the ALB over HTTP inside the VPC | TLS for any other service-to-service traffic | Yes |
| 164.316(b)(2)(i) | Keep documentation 6 years (Required) | LOG-02, LOG-08 | The 2190-day floor applies only with `compliance.frameworks: [hipaa]` | List the framework; keep policies and records outside the landing zone too | Yes |

## DORA (Regulation (EU) 2022/2554)

| Article | Requirement | Controls | Default | You still do | ID checked |
|:--|:--|:--|:--|:--|:--|
| Art. 6, 8 | ICT risk management framework; identification and asset inventory | LOG-11, GRD-09 | On (required-tag reporting: opt-in) | The framework and its yearly review | Yes |
| Art. 9(2) to 9(4) | Protection and prevention: access, authentication, encryption, network management, change management, patching | IAM-02, IAM-05, IAM-16, DP-01, DP-04, NET-05, NET-11, CHG-01, VUL-04 | On, except encryption in transit, which is partial (see HIPAA 164.312(e)(1)); NET-11 Regulated; MFA enforcement Manual | Documented policies and procedures | Yes |
| Art. 10 | Detection | DET-01, DET-02, DET-03, LOG-05 | On | Monitoring capability and staffing | Yes |
| Art. 11 | Response and recovery | DET-05 | DET-05 Scaffold (the handler only logs); `docs/runbooks/disaster-recovery.md`: Docs | Business continuity policy, crisis communication; the response actions themselves | Yes |
| Art. 12(1) to 12(3) | Backup policies; backup systems and periodic tests; restore to systems segregated from the source | BCK-01, BCK-02, BCK-03, BCK-07 | BCK-01 copy Off, On in a production scaffold; BCK-02 On, effective with BCK-01; BCK-07 Regulated | Turn the copy on; write restoration procedures | Yes |
| Art. 12(6) | Recovery time and recovery point objectives | BCK-03 | `docs/runbooks/disaster-recovery.md`: Docs (design targets) | Set and approve the objectives | Yes |
| Art. 17 | ICT-related incident management process | DET-05 | `docs/runbooks/regulatory-notification.md`: Docs | Classification criteria (Delegated Regulation (EU) 2024/1772) | Yes |
| Art. 19 | Report major ICT-related incidents | none in code | `docs/runbooks/regulatory-notification.md`: Docs (4 h, 72 h, 1 month) | Submit the reports | Yes |
| Art. 24, 25 | Digital operational resilience testing | BCK-02 | On with BCK-01; tabletop in `docs/runbooks/regulatory-notification.md` | Test programme; threat-led penetration testing where Art. 26 applies | Yes |
| Art. 28(3) | Register of information on ICT third-party providers | none in code | `docs/compliance/third-parties.md`: Docs | Keep the register in the supervisors' template | Yes |
| Art. 28(8) | Exit strategies | CHG-07 | `.github/workflows/state-backup.yml` On once its targets are set; exit column in `docs/compliance/third-parties.md` | Test the exit plan | Yes |
| Art. 30 | Key contractual provisions | none | Customer | Contracts | Yes |

## NIST SP 800-53 Rev 5

The matrix's NIST column is the primary Rev 5 mapping. The rows below name the
enhancements that a reviewer asks about most, and the gaps.

| Control | Title (Rev 5) | Controls | Default |
|:--|:--|:--|:--|
| AU-9(2) | Store on separate physical systems or components | LOG-08, CHG-07 | LOG-08 On; CHG-07 Off until its secret is set |
| AU-9(4) | Access by subset of privileged users | LOG-04, LOG-08 | AWS On (log archive account); GCP Off, required for Regulated |
| AU-11 | Audit record retention | LOG-02, LOG-08 | On (365 days; floors per `compliance.frameworks`) |
| CP-6, CP-9(8) | Alternate storage site; cryptographic protection of backups | BCK-01, BCK-03 | Off; On in a production scaffold (central copy) |
| SC-8(1), SC-13 | Cryptographic protection in transit; cryptographic protection | DP-01, DP-04 | On; HSM keys opt-in (`gcp.audit_key_protection_level: HSM`) |
| SI-2(2) | Automated flaw remediation status | VUL-04, VUL-05 | On |
| SA-9(5) | Processing, storage and service location | DP-09 | On when an allowed-region list is set |
| AC-6(5) | Privileged accounts | IAM-06, IAM-14 | On |
| IA-2(1), IA-2(2) | MFA to privileged and non-privileged accounts | IAM-16 | Manual (alert On) |

Not covered: SI-7(1) integrity checks on hosts (no file integrity monitoring,
DET-06); IA-2(1) enforcement (identity provider side, IAM-16); SC-13 with
FIPS-validated endpoints (no provider sets `use_fips_endpoint`).

## FedRAMP Moderate (Rev 5), reference only

FedRAMP authorization is **out of scope** (see below). For teams that use the
Moderate baseline as a reference:

| Control | Expectation | Landing-zone state | ID checked |
|:--|:--|:--|:--|
| AU-11 | OMB M-21-31: 12 months active storage and 18 months cold storage | `compliance.frameworks: [fedramp_moderate]` raises the retention floor to 913 days | Yes |
| AU-9(4) | Separate audit-management privilege | LOG-04 (GCP logging project), log archive account (AWS) | Yes |
| CM-7(2) | Prevent program execution | Allowed AMIs in the root declarative policy: audit mode by default (records, blocks nothing), `ec2_allowed_images.state = "enabled"` blocks other AMIs (`modules/aws/governance/organization-policy/variables.tf`). No application allow-listing on hosts | Yes |
| IR-6 | Incident reporting | No automation. `docs/runbooks/regulatory-notification.md` does not cover FedRAMP reporting times | Yes (ID); FedRAMP time limits not checked |
| SC-13 | FIPS-validated cryptography | Not configured: no FIPS endpoints. Cloud HSM keys are FIPS 140-2 Level 3 (`gcp.audit_key_protection_level: HSM`, DP-01) | Yes |
| SI-4(4) | Inbound and outbound communications traffic | NET-05 (AWS), LOG-06 and NET-03 (GCP) | Yes |
| SI-4(5) | System-generated alerts | LOG-05, LOG-09, LOG-10 | Yes |

"Yes" here means the control is in the NIST SP 800-53 Rev 5 Moderate baseline.
The FedRAMP-specific parameter values were not checked, except AU-11 against
OMB M-21-31.

## ISO/IEC 27001:2022

The matrix's ISO column is the Annex A crosswalk. These Annex A controls are
supported by documents or controls that are easy to miss there:

| Annex A | Title | Where |
|:--|:--|:--|
| A.5.12, A.5.13 | Classification and labelling of information | GRD-09 (`DataClassification` tag, GCP `data-classification` tag) |
| A.5.19 to A.5.22 | Supplier relationships, agreements, ICT supply chain, supplier service monitoring | `docs/compliance/third-parties.md`, DP-09 |
| A.5.24 to A.5.26 | Incident management planning, assessment, response | DET-05, `docs/runbooks/regulatory-notification.md` |
| A.5.29, A.5.30 | Security during disruption; ICT readiness for business continuity | BCK-01, BCK-03, `docs/runbooks/disaster-recovery.md` |
| A.8.5 | Secure authentication | IAM-16 (manual enforcement) |
| A.8.8 | Management of technical vulnerabilities | VUL-01 to VUL-06, DET-07 (manual SCC tier) |
| A.8.13 | Information backup | BCK-01 to BCK-07 |
| A.8.16 | Monitoring activities | LOG-05, LOG-09, LOG-10, DET-01 to DET-03; not file integrity (DET-06) |
| A.8.24 | Use of cryptography | DP-01, DP-02, DP-04 |

## Out of scope (stated plainly)

| Regime or capability | Why | What would change it |
|:--|:--|:--|
| FedRAMP Moderate or High authorization; DoD IL4 or IL5 | Needs an authorized boundary, FIPS endpoints, GovCloud or Assured Workloads, and continuous monitoring deliverables | A dedicated fork on GovCloud and Assured Workloads |
| Google Assured Workloads (FedRAMP, CJIS, ITAR, EU data boundary) | No `google_assured_workloads_workload` resource in this repository | A new organization stage option that creates the folder through Assured Workloads |
| AWS GovCloud (US) and the AWS European Sovereign Cloud | They pass input validation only. They are untested; service availability differs; FIPS endpoints are not configured (`use_fips_endpoint` is not set on any provider). See [Known Gaps](../known-gaps.md) | A sandbox in the partition |
| Google sovereign offers (for example partner-operated clouds) | A different control plane and APIs | Out of scope |
| HITRUST, SOX IT general controls | Certification programmes over your organization, not code | Your audit |
| PCI cardholder-data segmentation inside an environment | The regulated class is per environment, not per subnet or tier | Per-tier firewall policies with tag-based rules |
| File integrity monitoring, SCC tier activation, MFA enforcement | No Terraform API or a host agent is needed (DET-06, DET-07, IAM-16) | Your tooling and the manual steps in [Production Hardening](../runbooks/production-hardening.md#4-manual-identity-and-posture-steps) |

## How the IDs were checked

Checked on 2026-11-12.

| Framework | Source | Result |
|:--|:--|:--|
| PCI DSS v4.0.1 | The PCI Security Standards Council library needs a sign-in, so the standard was not read. Requirement numbers were checked against the PCI DSS v4.0.1 mappings in the AWS Security Hub control reference ([IAM](https://docs.aws.amazon.com/securityhub/latest/userguide/iam-controls.html), [CloudTrail](https://docs.aws.amazon.com/securityhub/latest/userguide/cloudtrail-controls.html), [S3](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html), [Systems Manager](https://docs.aws.amazon.com/securityhub/latest/userguide/ssm-controls.html), [GuardDuty](https://docs.aws.amazon.com/securityhub/latest/userguide/guardduty-controls.html), [Inspector](https://docs.aws.amazon.com/securityhub/latest/userguide/inspector-controls.html), [CloudFront](https://docs.aws.amazon.com/securityhub/latest/userguide/cloudfront-controls.html), [KMS](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html), [EC2](https://docs.aws.amazon.com/securityhub/latest/userguide/ec2-controls.html)) | Seen there: 1.3.1, 1.4.4, 2.2.1, 2.2.6, 3.5.1, 3.7.4, 4.2.1, 6.3.3, 6.4.2, 8.4.2, 10.2.1, 10.3.2, 10.4.2, 10.5.1, 11.3.1, 11.5.1. Not seen (rows marked No): 1.2, 3.6, 5.2, 5.3, 6.4.1, 7.2, 10.3.3, 10.3.4, 10.4.1, 10.7.2, 11.4, 11.5.2, 12.8, 12.10.1. A secondary mapping is not the standard: read the standard before you rely on any row |
| HIPAA | [eCFR 45 CFR Part 164 Subpart C](https://www.ecfr.gov/current/title-45/subtitle-A/subchapter-C/part-164/subpart-C), read through the eCFR renderer API | Every section, paragraph and Required or Addressable label in the table matches |
| DORA | EUR-Lex refused automated access. Checked against an unofficial consolidated copy ([digital-operational-resilience-act.com](https://www.digital-operational-resilience-act.com/DORA_Articles.html)) | Article titles for Art. 5 to 30 and the paragraphs of Art. 9, 12 and 28 match. Confirm against the [Official Journal text](https://eur-lex.europa.eu/eli/reg/2022/2554/oj) |
| NIST SP 800-53 Rev 5 | NIST's OSCAL catalog and Moderate baseline profile (release 5.2.0) from [usnistgov/oscal-content](https://github.com/usnistgov/oscal-content) | Every control ID and title in this page matches; every FedRAMP row control is in the Moderate baseline |
| FedRAMP | Not read. AU-11 was checked against [OMB M-21-31](https://www.whitehouse.gov/wp-content/uploads/2021/08/M-21-31-Improving-the-Federal-Governments-Investigative-and-Remediation-Capabilities-Related-to-Cybersecurity-Incidents.pdf) Appendix C (12 months active, 18 months cold) | Other FedRAMP parameter values are not claimed |
| ISO/IEC 27001:2022 | The standard is sold by ISO and was not read. Annex A numbers and titles were checked against secondary listings only | Confirm against your copy of the standard |
