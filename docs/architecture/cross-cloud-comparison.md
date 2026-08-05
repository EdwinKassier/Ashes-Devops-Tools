# Cross-Cloud Capability Comparison

How the same capability is implemented across providers, so you can navigate
"where does X live for cloud Y" without learning each cloud's tree separately.
Each cell links the module (or notes N/A). Naming and structure conventions
differ by cloud because each mirrors its own provider ecosystem — see the notes.

## Foundation / organization

| Capability | GCP | AWS | SaaS |
|---|---|---|---|
| Control-plane root | [`envs/gcp/organization`](../../envs/gcp/organization/) | [`envs/aws/organization`](../../envs/aws/organization/) | — |
| Org / hierarchy | [`gcp/stages/organization`](../../modules/gcp/stages/organization/) (folders) | [`aws/organization`](../../modules/aws/governance/organization/) (OUs) | — |
| Guardrail policies | [`gcp/governance/org-policy`](../../modules/gcp/governance/org-policy/) (org policies) | [`aws/organization-policy`](../../modules/aws/governance/organization-policy/) (SCP/RCP/declarative) | — |
| Automation identity | WIF + impersonation ([`gcp/iam/workload-identity`](../../modules/gcp/iam/workload-identity/)) | TFC dynamic OIDC / assume-role | provider API tokens |

## Networking

| Capability | GCP | AWS |
|---|---|---|
| Virtual network | [`gcp/network/vpc`](../../modules/gcp/network/vpc/) | [`aws/vpc`](../../modules/aws/network/vpc/) |
| Subnets | [`gcp/network/subnet`](../../modules/gcp/network/subnet/) | (tiers inside `aws/vpc`) |
| Hub / transit | Shared VPC + hub ([`gcp/stages/network-hub`](../../modules/gcp/stages/network-hub/)) | [`aws/transit-gateway`](../../modules/aws/network/transit-gateway/) |
| Firewall | [`gcp/network/network-firewall`](../../modules/gcp/network/network-firewall/), `hierarchical-firewall` | [`aws/network-firewall`](../../modules/aws/network/network-firewall/) |
| Private connectivity | [`gcp/network/psc`](../../modules/gcp/network/) / PSA | [`aws/vpc-endpoints`](../../modules/aws/network/vpc-endpoints/) |
| DNS | [`gcp/network/dns`](../../modules/gcp/network/dns/) | [`aws/route53-resolver`](../../modules/aws/network/route53-resolver/) |
| WAF / edge | [`gcp/network/cloud-armor`](../../modules/gcp/network/cloud-armor/) | [`aws/edge-security`](../../modules/aws/security/edge-security/) (WAF/FMS) |
| IP address mgmt | (project CIDRs) | [`aws/ipam`](../../modules/aws/network/ipam/) |
| Service perimeter | [`gcp/network/vpc-sc`](../../modules/gcp/network/vpc-sc/) | (RCP data perimeter in `organization-policy`) |

## Security & detection

| Capability | GCP | AWS |
|---|---|---|
| Audit logging | [`gcp/governance/cloud-audit-logs`](../../modules/gcp/governance/cloud-audit-logs/) | [`aws/cloudtrail-org`](../../modules/aws/security/cloudtrail-org/) |
| Posture / findings | [`gcp/governance/scc`](../../modules/gcp/governance/scc/) (SCC) | [`aws/securityhub-org`](../../modules/aws/security/securityhub-org/) |
| Config/compliance | (org policies) | [`aws/config-org`](../../modules/aws/security/config-org/) |
| Threat detection | SCC / (partner) | [`aws/guardduty-org`](../../modules/aws/security/guardduty-org/) |
| Access analysis | IAM Recommender | [`aws/access-analyzer-org`](../../modules/aws/security/access-analyzer-org/) |
| Central log store | audit-logs bucket/BQ | [`aws/log-archive-bucket`](../../modules/aws/data/log-archive-bucket/) + [`securitylake`](../../modules/aws/security/securitylake/) |
| Encryption keys | [`gcp/governance/kms`](../../modules/gcp/governance/kms/) (CMEK) | [`aws/kms-key`](../../modules/aws/data/kms-key/) |

## Identity, backup, storage

| Capability | GCP | AWS |
|---|---|---|
| Human SSO | Cloud Identity groups | [`aws/iam-identity-center`](../../modules/aws/iam/iam-identity-center/) |
| Custom roles | [`gcp/iam/role`](../../modules/gcp/iam/role/) | [`aws/iam-role`](../../modules/aws/iam/iam-role/) |
| Backup | (snapshot schedules) | [`aws/backup-vault`](../../modules/aws/backup/backup-vault/) + `backup-org-policy` |
| Object storage | [`gcp/cloud-storage`](../../modules/gcp/cloud-storage/) | (per-module S3, e.g. `log-archive-bucket`) |
| Artifacts | [`gcp/artifact-registry`](../../modules/gcp/artifact-registry/) | (ECR — not yet modularized) |

## SaaS

| Capability | Supabase | Vercel |
|---|---|---|
| Project | [`supabase/project`](../../modules/supabase/project/) | [`vercel/project`](../../modules/vercel/project/) |
| Settings | [`supabase/settings`](../../modules/supabase/settings/) | (in `vercel/project`) |
| Secrets | [`supabase/vault-secrets`](../../modules/supabase/vault-secrets/) | project env vars (in `vercel/project`) |
| Full environment | [`saas/stages/saas-workload`](../../modules/saas/stages/saas-workload/) composes both | |

## Convention notes (intentional per-cloud differences)

- **Module grouping:** both `modules/gcp/` and `modules/aws/` are organized into
  category subdirs (`network/`, `iam/`, `governance/`, `security/`, `data/`, …),
  each with an index README ([gcp](../../modules/gcp/), [aws](../../modules/aws/README.md)).
  The category sets differ where the clouds differ (AWS has a large `security/`
  group; GCP has `monitoring/`), but `network`/`iam`/`governance` line up for
  direct comparison.
- **Output naming:** GCP modules use the Cloud Foundation Toolkit convention
  (unprefixed `id`, `self_link`); AWS modules use the community convention
  (`vpc_id`, `subnet_ids_by_tier`). Each mirrors its ecosystem — consumers wiring
  multi-cloud roots should expect per-cloud output vocabularies.
- **Env roots:** AWS has more deployable roots (SRA mandates more accounts:
  security, network, identity, shared-services, backup); GCP folds security and
  networking into the organization + workload roots. See [`envs/README.md`](../../envs/README.md).
