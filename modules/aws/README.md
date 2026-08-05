# AWS Modules

AWS-native Terraform modules implementing the [AWS Security Reference
Architecture](../../docs/architecture/aws-landing-zone.md). Primitives are
grouped into category subdirectories (mirroring [`modules/gcp/`](../gcp/));
orchestration wrappers live under [`modules/aws/stages/`](./stages/).

> Cross-provider comparison (AWS vs GCP capabilities): [`docs/architecture/cross-cloud-comparison.md`](../../docs/architecture/cross-cloud-comparison.md).

## `governance/` — Organization & guardrails
| Module | Purpose |
|--------|---------|
| [organization](./governance/organization/) | AWS Organizations org + OUs, `feature_set = ALL` from creation |
| [organization-policy](./governance/organization-policy/) | SCPs, RCPs, and declarative policies (region restriction, data perimeter, IMDSv2) |
| [iam-organizations-features](./governance/iam-organizations-features/) | Centralized root-access management |
| [account](./governance/account/) | Member account creation |
| [account-baseline](./governance/account-baseline/) | Per-account guardrails: EBS default encryption, account S3 Block Public Access, password policy |
| [cost-governance](./governance/cost-governance/) | Budgets and cost allocation |
| [service-quotas](./governance/service-quotas/) | Service quota management |

## `security/` — Detection & response (delegated-admin)
| Module | Purpose |
|--------|---------|
| [security-delegated-admin](./security/security-delegated-admin/) | Registers delegated admins for security services (excludes those with dedicated `*_organization_admin_account` resources) |
| [org-security-service](./security/org-security-service/) | Org enablement for Macie / Inspector / Detective / Resource Explorer |
| [guardduty-org](./security/guardduty-org/) | GuardDuty organization (Runtime Monitoring, optional EBS malware) |
| [securityhub-org](./security/securityhub-org/) | Security Hub organization (central configuration) |
| [config-org](./security/config-org/) | AWS Config org recorder + aggregator |
| [cloudtrail-org](./security/cloudtrail-org/) | Organization CloudTrail |
| [access-analyzer-org](./security/access-analyzer-org/) | IAM Access Analyzer (external + unused access) |
| [securitylake](./security/securitylake/) | Security Lake + subscriber |
| [security-notifications](./security/security-notifications/) | Security alerting fan-out |
| [incident-response](./security/incident-response/) | Incident-response scaffolding |
| [firewall-manager-org](./security/firewall-manager-org/) | Firewall Manager organization |
| [secrets-baseline](./security/secrets-baseline/) | Secrets Manager baseline |
| [edge-security](./security/edge-security/) | WAF / edge protection |

## `network/`
| Module | Purpose |
|--------|---------|
| [vpc](./network/vpc/) | VPC with tiered subnets |
| [vpc-endpoints](./network/vpc-endpoints/) | Interface / gateway VPC endpoints |
| [transit-gateway](./network/transit-gateway/) | Transit Gateway with prod/nonprod route-table isolation |
| [network-firewall](./network/network-firewall/) | AWS Network Firewall |
| [route53-resolver](./network/route53-resolver/) | Route 53 Resolver endpoints/rules |
| [network-access-analyzer](./network/network-access-analyzer/) | Network Access Analyzer scopes |
| [ipam](./network/ipam/) | IP Address Manager |

## `iam/`
| Module | Purpose |
|--------|---------|
| [iam-role](./iam/iam-role/) | Custom IAM role (policy JSON via `jsonencode`) |
| [iam-identity-center](./iam/iam-identity-center/) | IAM Identity Center / SSO permission sets + assignments |

## `data/` — Keys, storage & PKI
| Module | Purpose |
|--------|---------|
| [kms-key](./data/kms-key/) | KMS CMK with rotation + log-service grants |
| [log-archive-bucket](./data/log-archive-bucket/) | Immutable (Object Lock COMPLIANCE) log-archive S3 bucket |
| [private-ca](./data/private-ca/) | ACM Private CA |

## `backup/`
| Module | Purpose |
|--------|---------|
| [backup-vault](./backup/backup-vault/) | Backup vault with Vault Lock (compliance mode) + restore testing |
| [backup-org-policy](./backup/backup-org-policy/) | Organization backup policy |

## `ops/`
| Module | Purpose |
|--------|---------|
| [systems-manager](./ops/systems-manager/) | Systems Manager (SSM) baseline |

---

**Provider pin:** every AWS module pins `aws = ">= 6.46.0, < 7.0.0"` (deliberate floored pin — see [CLAUDE.md](../../CLAUDE.md) AWS gotchas). **Cross-account modules** declare `configuration_aliases` and cannot be root-`terraform validate`d standalone (CI skips them; covered by `examples/`, composing stages, and `mock_provider` tests).
