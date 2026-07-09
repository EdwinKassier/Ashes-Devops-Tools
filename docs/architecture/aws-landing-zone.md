# AWS Landing Zone

This document is the authoritative description of the AWS landing zone deployed by this repository: the account and OU model, which root deploys which layer, the network topology, the security services and guardrails, the cost profile of the always-on baseline, and the IPv6 posture. It implements the **AWS Security Reference Architecture (SRA)** on top of the [per-cloud-root model](provider-selection.md) — AWS lives entirely in `envs/aws-*` roots, physically separate from the GCP control plane so that neither cloud forces the other's credentials.

For how to *stand this up* see [`docs/runbooks/aws-bootstrap.md`](../runbooks/aws-bootstrap.md); for the cross-root wiring contract see [`docs/architecture/adding-a-cloud.md`](adding-a-cloud.md).

---

## Account & OU model

The organization follows the AWS SRA foundational layout: a small set of purpose-built member accounts hung off an OU tree, with the management (payer) account holding the org root and running no workloads.

```mermaid
graph TB
    root["Org Root (r-xxxx)"]

    subgraph mgmt["Management / Payer account"]
        mgmt_note["Org root, billing, SCP/RCP owner<br/>No workloads. Never SCP-restricted."]
    end

    root --> mgmt

    subgraph ou_sec["OU: Security"]
        acct_log["Log Archive account<br/>(WORM log bucket)"]
        acct_sec["Security Tooling account<br/>(delegated admin)"]
        acct_forensics["Forensics account<br/>(clean-room)"]
    end

    subgraph ou_infra["OU: Infrastructure"]
        acct_net["Network account<br/>(TGW hub, egress, DNS)"]
        acct_shared["Shared Services account<br/>(Identity Center, platform)"]
        acct_backup["Backup account<br/>(central vaults)"]
    end

    subgraph ou_work["OU: Workloads"]
        ou_prod["OU: Prod<br/>workload accounts"]
        ou_nonprod["OU: NonProd<br/>workload accounts"]
    end

    subgraph ou_other["Other top-level OUs"]
        ou_sandbox["Sandbox"]
        ou_susp["Suspended"]
        ou_stage["PolicyStaging"]
        ou_exc["Exceptions"]
        ou_trans["Transitional"]
    end

    root --> ou_sec
    root --> ou_infra
    root --> ou_work
    root --> ou_other
```

**Top-level OUs** (`modules/aws/organization` var `top_level_ous`, default the SRA set): `Security`, `Infrastructure`, `Workloads`, `Sandbox`, `Suspended`, `PolicyStaging`, `Exceptions`, `Transitional`. **Child OUs** under `Workloads` (`child_ous`): `Prod` and `NonProd`.

**Foundational accounts** (`envs/aws-organization/terraform.tfvars` `accounts` map, keyed by name with an `ou` placement):

| Account key | OU | Purpose |
|---|---|---|
| `log_archive` | Security | Immutable log archive — the WORM S3 bucket (`modules/aws/log-archive-bucket`). |
| `security_tooling` | Security | Delegated administrator for GuardDuty, Security Hub, Config aggregator, Access Analyzer, Macie, Inspector, Detective, Security Lake. |
| `forensics` | Security | Isolated clean-room account for incident investigation and cross-account EBS-snapshot analysis. |
| `network` | Infrastructure | Transit Gateway hub, centralized egress/inspection, IPAM, Route 53 resolver. |
| `shared_services` | Infrastructure | IAM Identity Center delegated admin, shared platform services. |
| `backup` | Infrastructure | Centralized AWS Backup vaults and org backup plan. |
| `<workload>` | Workloads/Prod or Workloads/NonProd | Per-environment workload accounts (`workload_accounts` map). |

The account keys are the exact keys of the `account_ids` / `account_role_arns` outputs the org root publishes — the [cross-root contract](adding-a-cloud.md#4-stable-output-keys-are-the-cross-root-contract).

---

## Layer map — which root deploys what

Each layer is one root = one Terraform Cloud workspace (see [provider-selection](provider-selection.md)). Ordering is enforced by **apply order + remote-state reads**, not by any cross-root `depends_on`.

| Order | Root | Workspace | Deploys | Stage module |
|---|---|---|---|---|
| 1 | `envs/aws-organization` | `aws-organization` | Org, SRA OU tree, foundational accounts, guardrails (SCP/RCP/declarative/tag/backup). Publishes `account_ids`, `account_role_arns`. | `modules/stages/aws-organization` |
| 2 | `envs/aws-security` | `aws-security` | Log archive (WORM), org CloudTrail, Config aggregator, GuardDuty, Security Hub CSPM, Access Analyzer, Security Lake, delegated-admin wiring, incident-response. | `modules/stages/aws-security` |
| 3 | `envs/aws-network` | `aws-network` | TGW hub, inspection VPC + Network Firewall, centralized egress (NAT), IPAM, centralized VPC endpoints, Route 53 resolver/DNS firewall. | `modules/stages/aws-network-hub` |
| 4 | `envs/aws-identity` | `aws-identity` | IAM Identity Center permission sets and account assignments (after Identity Center is delegated to Shared Services). | — |
| 5 | `envs/aws-shared-services` | `aws-shared-services` | Shared platform services (optional / gated). | `modules/stages/aws-shared-services` |
| 6 | `envs/aws-backup` | `aws-backup` | Centralized backup vaults (Vault Lock) and org backup plan. | `modules/stages/aws-backup` |
| 7 | `envs/aws-workload` | `aws-workload-<env>` | Per-env spoke VPC, workload roles, per-account baseline. One workspace per env via the `aws-workload-` prefix. | `modules/stages/aws-workload` |
| — | `envs/saas` | `saas-<name>` | Supabase and/or Vercel only. **No AWS provider** — reads AWS/GCP remote state for values but configures no AWS credentials. | `modules/stages/saas-workload` |

The **minimum governed footprint** is `aws-organization` + `aws-security`; everything from `aws-network` down is additive. The `saas` root is deliberately outside the AWS chain: it is selected purely by whether you apply its workspace, and it needs no AWS credentials.

---

## Network topology

A Transit Gateway hub-and-spoke in the Network account, with prod/nonprod route-table segmentation, a centralized inspection VPC fronted by AWS Network Firewall, centralized egress via NAT, IPAM-managed CIDRs, centralized interface VPC endpoints, and Route 53 Resolver with DNS Firewall.

```mermaid
graph TB
    subgraph net["Network account (Infrastructure OU)"]
        tgw["Transit Gateway<br/>(hub)"]

        subgraph inspection["Inspection VPC"]
            nfw["Network Firewall<br/>(per-AZ endpoint)"]
            nat["NAT Gateway<br/>(centralized egress)"]
        end

        subgraph endpoints_vpc["Endpoints VPC"]
            r53["Route 53 Resolver<br/>+ DNS Firewall"]
            vpce["Centralized interface<br/>VPC endpoints"]
        end

        ipam["IPAM<br/>(CIDR allocation)"]
    end

    subgraph prod_rt["TGW route table: Prod"]
        prod_spoke["Prod spoke VPCs<br/>(workload accounts)"]
    end

    subgraph nonprod_rt["TGW route table: NonProd"]
        nonprod_spoke["NonProd spoke VPCs<br/>(workload accounts)"]
    end

    igw(("Internet"))

    prod_spoke -->|"attachment"| tgw
    nonprod_spoke -->|"attachment"| tgw
    tgw -->|"default route"| inspection
    inspection --> nfw
    nfw --> nat
    nat --> igw
    tgw --> endpoints_vpc
    ipam -.->|"allocates CIDRs"| prod_spoke
    ipam -.->|"allocates CIDRs"| nonprod_spoke
    prod_spoke -.->|"resolves via"| r53
    nonprod_spoke -.->|"resolves via"| r53
```

- **Segmentation.** Prod and NonProd spokes attach to the same TGW but use **separate route tables**, so prod↔nonprod lateral traffic is not routable by default; both send egress/inter-VPC traffic through the inspection VPC.
- **Centralized inspection.** All north-south (and configurable east-west) traffic is default-routed to the inspection VPC, where **AWS Network Firewall** (`modules/aws/network-firewall`) inspects it before it reaches the NAT gateway.
- **Centralized egress.** NAT lives once in the Network account, not per spoke — spokes have no NAT of their own.
- **IPAM.** `modules/aws/ipam` owns the address plan; spoke CIDRs are allocated from IPAM pools to prevent overlap.
- **Centralized endpoints.** Interface VPC endpoints (`modules/aws/vpc-endpoints`) are created once and shared over the TGW, so spokes reach AWS APIs privately without per-VPC endpoint sprawl.
- **DNS.** `modules/aws/route53-resolver` provides inbound/outbound resolver endpoints and a **DNS Firewall** for domain-level egress control.
- **Analysis.** `modules/aws/network-access-analyzer` provides reachability analysis over the topology.

---

## Security services

The SRA security stack is delegated from the management account to the **Security Tooling** account, which is the single delegated administrator for the org-wide services. The **Log Archive** account is the immutable sink.

| Service | Module | Delegation / notes |
|---|---|---|
| CloudTrail (org trail) | `modules/aws/cloudtrail-org` | Org-wide multi-Region trail → Log Archive bucket. |
| AWS Config (org) | `modules/aws/config-org` | Recorder per Region + org aggregator in Security Tooling. |
| GuardDuty (org) | `modules/aws/guardduty-org` | Delegated admin; auto-enroll new accounts; EBS malware protection. |
| Security Hub CSPM | `modules/aws/securityhub-org` | Central configuration policy associated at the org root. |
| Access Analyzer (org) | `modules/aws/access-analyzer-org` | Org-scoped external/unused-access analyzers. |
| Macie / Inspector / Detective | via `modules/aws/org-security-service` / `security-delegated-admin` | Delegated to Security Tooling. |
| Security Lake | `modules/aws/securitylake` | Normalized OCSF lake; **cost-gated** (see below). |
| Systems Manager | `modules/aws/systems-manager` | Fleet/patch baseline. |
| Firewall Manager | `modules/aws/firewall-manager-org` | Org-wide WAF/SG policy. |
| Incident response | `modules/aws/incident-response` | GuardDuty→EventBridge→isolation Lambda; forensics snapshot-share role. |
| Notifications | `modules/aws/security-notifications` | Finding fan-out. |

### Guardrails

`modules/aws/organization-policy` renders all five AWS Organizations policy types:

- **SCPs** (three): `deny-tamper` (protect logging/security config), `region-restriction`, and a `baseline` deny set.
- **RCP** (resource control policy): a two-statement data perimeter (org-identity + confused-deputy + secure-transport / `aws:PrincipalOrgID`).
- **Declarative** EC2 policy (`@@assign`): enforce IMDSv2, block public AMIs / public access.
- **Tag policy**: enforce required tags.
- **Backup policy**: daily org backup plan.

`FullAWSAccess` / `RCPFullAWSAccess` remain AWS-managed and are never managed here.

### Root-access management & break-glass

- The **management account is never restricted by SCPs** — AWS does not apply SCPs to the org root's own account. It must therefore be secured out-of-band: hardware MFA on root, no root access keys. See [`aws-break-glass.md`](../runbooks/aws-break-glass.md).
- The **break-glass role** ARN (`break_glass_role_arn`) is an account-qualified exact ARN that is **carved out of every guardrail deny statement**, so a genuine incident can bypass the SCPs. It is disabled-by-default (deny-all standing policy) and MFA-required.

### Incident response & forensics

`modules/aws/incident-response` wires a GuardDuty finding (severity ≥ 7) → EventBridge rule → isolation Lambda (attach quarantine SG). The `ir-forensics-snapshot-share` role is trusted only by the **Forensics account** principal and further scoped by `aws:PrincipalOrgID`, for cross-account EBS-snapshot sharing into the forensics clean-room. See [`aws-incident-response.md`](../runbooks/aws-incident-response.md).

---

## Cost of the security baseline

The governed baseline is intentionally always-on, but several services dominate the bill. Each is gated so you can right-size for a given environment:

| Service | Cost driver | Toggle | Default |
|---|---|---|---|
| AWS Config | Records **all** supported resource types in **every Region** — the most expensive Config mode. | `record_all_supported` (`modules/aws/config-org`) | `true` |
| Security Lake | Ingestion + storage + OCSF normalization charges. | `enable_security_lake` (`modules/aws/securitylake`) | `true` |
| Network Firewall | Billed **per endpoint-hour** (one endpoint per firewall subnet, i.e. per-AZ) plus per-GB processed. | `enable_network_firewall` (`modules/aws/network-firewall`) | `true` |
| GuardDuty EBS malware | Agentless EBS malware scanning billed per GB scanned. | `enable_ebs_malware_protection` (`modules/aws/guardduty-org`) | `true` |
| Any Regional service | Cost scales with the number of enabled Regions. | Per-Region enable lists on the relevant roots. | — |

Right-sizing guidance: for cost-sensitive non-prod, set `record_all_supported = false` (and pair with a narrower recording group managed out-of-band), consider `enable_security_lake = false`, reduce the per-AZ Network Firewall footprint or set `enable_network_firewall = false` where a spoke does not need inline inspection, and disable `enable_ebs_malware_protection` where agentless scanning is not required. Keep the full set on for prod.

---

## IPv6 posture

The landing zone is **IPv4-only by default**. The `modules/aws/vpc` module exposes an `enable_ipv6` variable (default `false`) that assigns an Amazon-provided `/56` IPv6 CIDR block to the VPC, providing a dual-stack path when a specific workload needs it. Enable it per-VPC rather than org-wide; the TGW segmentation and inspection topology above are described for the default IPv4 case.

---

## SRA Conformance Checklist

This table maps each AWS Security Reference Architecture (or associated best-practice) control to the module and/or root that **implements** it in this repository. Every row was confirmed against the module source, not just its README.

| Control | SRA / best-practice source | Implemented by | Notes |
|---|---|---|---|
| Multi-account organization with SRA OU tree | SRA "Organization structure"; *Organizing Your AWS Environment* whitepaper | `modules/aws/organization` (`top_level_ous`, `child_ous`); `envs/aws-organization` | Default `top_level_ous` = `Security`, `Infrastructure`, `Workloads`, `Sandbox`, `Suspended`, `PolicyStaging`, `Exceptions`, `Transitional`; `child_ous` = `Prod`, `NonProd` under `Workloads`. |
| Foundational accounts (Log Archive, Security Tooling, Network, Shared Services, Backup, Forensics) | SRA "Dedicated accounts for security functions" | `modules/aws/account` (member-account vending, `for_each`) + the `accounts` map in `modules/stages/aws-organization` / `envs/aws-organization/terraform.tfvars` | Stage merges `accounts` + `workload_accounts` and vends one `account` per key; each is placed in its OU. Forensics is a dedicated clean-room account in the Security OU. |
| SCP + RCP + declarative + tag + backup guardrails | SRA "Guardrails"; AWS Organizations policy types | `modules/aws/organization-policy` (all five types); `modules/aws/backup-org-policy` (`BACKUP_POLICY`) | SCPs: `deny-tamper`, `region-restriction`, `baseline`. RCP: data-perimeter (org-identity + confused-deputy + secure-transport / `aws:PrincipalOrgID`). Declarative EC2 policy: `@@assign` IMDSv2 + block public AMI/access. Tag policy: required tags. `FullAWSAccess`/`RCPFullAWSAccess` left AWS-managed. |
| Centralized root-access management | SRA "Manage root access centrally"; IAM organization features | `modules/aws/iam-organizations-features` | Enables `RootCredentialsManagement` + `RootSessions` (both by default); removes standing root credentials from member accounts. |
| Org CloudTrail (multi-Region, log-file validation, SSE-KMS, Object Lock, BPA) | SRA "Log Archive account" / CloudTrail baseline | `modules/aws/cloudtrail-org` + `modules/aws/log-archive-bucket` | Trail: `is_multi_region_trail = true`, `include_global_service_events = true`, `enable_log_file_validation = true`, `kms_key_id` set. Bucket: `object_lock_enabled = true` with `object_lock_mode` default `COMPLIANCE` (WORM), all four BPA dimensions, versioning, SSE-KMS with bucket key. |
| AWS Config org aggregator + per-Region recorders + conformance packs | SRA "AWS Config" baseline | `modules/aws/config-org` | Per-Region recorder + delivery channel + status; org aggregator in Security Tooling; `aws_config_organization_conformance_pack` (opt-in, bring-your-own template). `recorder_only = true` mode skips aggregator/packs for per-workload recorders. |
| GuardDuty org-wide (auto_enable = ALL, protection plans) | SRA "GuardDuty" delegated admin | `modules/aws/guardduty-org` | `auto_enable_organization_members = "ALL"`; detector + protection-plan features per enabled Region; `enable_ebs_malware_protection` (cost-gated, default on). |
| Security Hub CENTRAL configuration (FSBP / CIS / NIST) | SRA "Security Hub" central config | `modules/aws/securityhub-org` | CENTRAL configuration policy associated at org root from the Security Tooling delegated admin; standard set defaults to FSBP + CIS 1.4 + NIST 800-53 r5 computed from `home_region`. |
| IAM Access Analyzer (external + unused) | SRA "IAM Access Analyzer" | `modules/aws/access-analyzer-org` | Two org-scoped analyzers: `external` and `unused` access. |
| Delegated admin = Security Tooling | SRA "Delegated administrator" | `modules/aws/security-delegated-admin` + the services' own dedicated admin resources | This module registers `aws_organizations_delegated_administrator` for services without a dedicated admin resource (Access Analyzer, Config, CloudTrail, FMS, SSM, Resource Explorer, Security Lake). GuardDuty/Macie/Inspector/Detective/Security Hub are delegated via their own dedicated resources in their respective modules. |
| Macie / Inspector / Detective / Resource Explorer | SRA "Additional security services" | `modules/aws/org-security-service` | `enabled_services` set gates `macie`, `inspector`, `detective`, `resource-explorer`. Default `["macie","inspector"]`; Detective OFF by default per SRA. |
| Amazon Security Lake (centralized analytics) | SRA "Security Lake" / OCSF analytics | `modules/aws/securitylake` | `aws_securitylake_data_lake` + `aws_securitylake_aws_log_source`; cost-gated via `enable_security_lake` (default true). |
| Firewall Manager | SRA "Firewall Manager" | `modules/aws/firewall-manager-org` | `aws_fms_admin_account` registered from the `aws.management` provider; FMS policies then owned by the Security Tooling admin. |
| Systems Manager / Session Manager baseline | SRA "Systems Manager" ops baseline | `modules/aws/systems-manager` | Session Manager preferences document forcing KMS-encrypted sessions + dual S3/CloudWatch logging (no plaintext shell); default patch baseline. |
| Incident response / forensics account + quarantine + isolation | SRA cyber-forensics companion | `modules/aws/incident-response` + the `forensics` account | GuardDuty finding (severity ≥ 7) → EventBridge rule → isolation Lambda (quarantine SG); `ir-forensics-snapshot-share` role trusted only by the Forensics account, scoped by `aws:PrincipalOrgID`. Lambda ships as an extendable scaffold. |
| Security notifications / EventBridge / break-glass alarm | SRA "Security notifications" | `modules/aws/security-notifications` | KMS-encrypted SNS topic + EventBridge rules fanning out findings (root usage, console sign-in without MFA, org-access-role and break-glass-role use). The break-glass detective alarm depends on the org CloudTrail delivering STS events. |
| Account-baseline defaults (default-EBS-encryption, S3 account BPA, password policy) | SRA "Account baseline"; per-account hardening | `modules/aws/account-baseline` | `aws_ebs_encryption_by_default` (+ optional `aws_ebs_default_kms_key`), `aws_s3_account_public_access_block` (all-true), `aws_iam_account_password_policy`. Default-VPC deletion is intentionally out-of-band (see below). |
| TGW hub-spoke with prod/nonprod segmentation | *Multi-VPC Network Infrastructure* whitepaper | `modules/aws/transit-gateway` | Default route-table association/propagation disabled; segmentation via per-segment `aws_ec2_transit_gateway_route_table` (Prod / NonProd), so prod↔nonprod is not routable by default. |
| Inspection VPC + Network Firewall + centralized egress | SRA "Network account"; centralized inspection | `modules/aws/network-firewall` + `modules/stages/aws-network-hub` | Stage builds an inspection VPC (Network Firewall endpoints) and an egress VPC; stage-level EIP+NAT per egress public subnet routes through the inspection attachment. `enable_network_firewall` cost-gated (default on). |
| IPAM (hierarchical, RAM-shared) | *Multi-VPC Network Infrastructure* whitepaper | `modules/aws/ipam` | Two-tier pool topology (top-level supernet → one regional pool per Region); regional pools shared org-wide via AWS RAM to the organization ARN. |
| Centralized VPC interface endpoints | SRA "Centralized VPC endpoints" | `modules/aws/vpc-endpoints` | Interface (PrivateLink) endpoints created once + shared private hosted zone, reached by spokes over the TGW. |
| Route 53 Resolver + Profiles + DNS Firewall + DNSSEC + query logging | SRA / *Multi-VPC Network Infrastructure* DNS design | `modules/aws/route53-resolver` | Inbound/outbound resolver endpoints; Route 53 Profile shared org-wide over RAM; DNS Firewall; query logging to central Log Archive; optional DNSSEC validation. |
| IAM Identity Center (permission sets, ABAC) | SRA "IAM Identity Center" | `modules/aws/iam-identity-center` | `aws_ssoadmin_permission_set` (+ inline/managed policies) and `aws_ssoadmin_account_assignment`; optional ABAC via `enable_abac` + `aws:PrincipalTag`. Operates within an already-existing Identity Center instance (enablement is out-of-band, see below). |
| Org Backup + Vault Lock (COMPLIANCE WORM) + restore testing | SRA "Backup account"; AWS Backup baseline | `modules/aws/backup-vault` + `modules/aws/backup-org-policy` | `aws_backup_vault_lock_configuration` in Compliance mode (non-null `changeable_for_days` → WORM, undeletable before `min_retention_days` by anyone incl. root); `aws_backup_restore_testing_plan` for periodic restore testing; org `BACKUP_POLICY` via `backup-org-policy`. |
| Cost governance (budgets, anomaly detection, cost-allocation tags) | AWS cost-management best practice | `modules/aws/cost-governance` | `aws_budgets_budget` (per-key monthly COST), `aws_ce_anomaly_monitor` + `aws_ce_anomaly_subscription` (daily email above impact threshold), `aws_ce_cost_allocation_tag` activating the tag-policy keys. Gated by `enable_cost_governance`. |
| Edge security (WAF / CloudFront / Shield / ACM) | SRA "Edge protection" | `modules/aws/edge-security` (optional) | CloudFront distribution + CloudFront-scoped WAFv2 Web ACL + optional ACM cert + optional Shield Advanced + optional WAF logging. Gated: `enable_edge` default `false`. |
| Private CA + org Secrets baseline | SRA "Certificate management" / secrets hygiene | `modules/aws/private-ca` + `modules/aws/secrets-baseline` (both gated) | ACM Private CA (ROOT or SUBORDINATE), `enable_private_ca` default `false` (fixed monthly per-CA charge). Secrets Manager secrets with org-scoped resource policies (`aws:PrincipalOrgID`), `enable_secrets_baseline` default `false`. |

**Out-of-band prerequisites** (must exist before or alongside Terraform, not modelled as `aws` resources in this repo):

- **IAM Identity Center instance enablement** — `modules/aws/iam-identity-center` configures permission sets/assignments/ABAC *within* an already-enabled instance; enabling the instance and delegating it to Shared Services is a manual gate between the `aws-organization` and `aws-identity` applies (see the layer map and [`aws-bootstrap.md`](../runbooks/aws-bootstrap.md)).
- **Management-account root hardening** — the payer account is never SCP-restricted, so hardware-MFA-on-root / no-root-access-keys is enforced out-of-band (see [`aws-break-glass.md`](../runbooks/aws-break-glass.md)).
- **Default-VPC-deletion StackSet** — a single root cannot fan out to every account and Region, so default-VPC deletion is an org-wide auto-deploying CloudFormation StackSet (bootstrap phase-0.5), not Terraform in this repo.
- **CloudWatch-primary logging via `awscc`** — routing logs to CloudWatch as the primary sink is an `awscc`/out-of-band enhancement (no plain `aws` resource); the S3 Log Archive bucket remains the immutable sink.

**Gated / optional** (present in the repo but disabled by default, opt-in per environment): `modules/aws/edge-security` (`enable_edge`), `modules/aws/private-ca` (`enable_private_ca`), `modules/aws/secrets-baseline` (`enable_secrets_baseline`), `modules/aws/service-quotas` (`enable_service_quotas`), `modules/aws/network-access-analyzer` (`enable_network_access_analyzer`), and Detective within `modules/aws/org-security-service` (off by default per SRA). Note also that `network-access-analyzer` manages only the reachability *scope* — scope *analyses* are run out-of-band.

---

## SRA citations

This architecture follows AWS Prescriptive Guidance. Primary sources:

- **AWS Security Reference Architecture (SRA)** — <https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html>
- **Organizing Your AWS Environment Using Multiple Accounts** (whitepaper, 2025-04-30) — <https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/organizing-your-aws-environment.html>
- **Building a Scalable and Secure Multi-VPC AWS Network Infrastructure** (whitepaper) — <https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/welcome.html>
- **AWS Security Reference Architecture: A cyber-forensics companion** — <https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture-cyber-forensics/welcome.html>

---

## See also

- [Provider Selection](provider-selection.md) — why one cloud = one root = one workspace.
- [Adding a Cloud](adding-a-cloud.md) — the cross-root contract.
- [AWS Bootstrap](../runbooks/aws-bootstrap.md) — phase-0 stand-up.
- [AWS Add Account](../runbooks/aws-add-account.md), [Break-Glass](../runbooks/aws-break-glass.md), [Incident Response](../runbooks/aws-incident-response.md), [Teardown](../runbooks/aws-teardown.md).
