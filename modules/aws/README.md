# AWS Modules

AWS-native Terraform modules implementing the [AWS Security Reference
Architecture](../../docs/architecture/aws-landing-zone.md). Primitives are flat
under `modules/aws/`; orchestration wrappers live under
[`modules/aws/stages/`](./stages/). Grouped below by domain for navigation
(the directories themselves are flat — the grouping is logical, mirroring the
category structure of [`modules/gcp/`](../gcp/)).

> Cross-provider comparison (AWS vs GCP capabilities): [`docs/architecture/cross-cloud-comparison.md`](../../docs/architecture/cross-cloud-comparison.md).

## Governance & Organization
| Module | Purpose |
|--------|---------|
| [organization](./organization/) | AWS Organizations org + OUs, `feature_set = ALL` from creation |
| [organization-policy](./organization-policy/) | SCPs, RCPs, and declarative policies (region restriction, data perimeter, IMDSv2) |
| [iam-organizations-features](./iam-organizations-features/) | Centralized root-access management |
| [account](./account/) | Member account creation |
| [account-baseline](./account-baseline/) | Per-account guardrails: EBS default encryption, account S3 Block Public Access, password policy |
| [cost-governance](./cost-governance/) | Budgets and cost allocation |
| [service-quotas](./service-quotas/) | Service quota management |

## Security & Detection (delegated-admin)
| Module | Purpose |
|--------|---------|
| [security-delegated-admin](./security-delegated-admin/) | Registers delegated admins for security services (excludes those with dedicated `*_organization_admin_account` resources) |
| [org-security-service](./org-security-service/) | Org enablement for Macie / Inspector / Detective / Resource Explorer (shared shape) |
| [guardduty-org](./guardduty-org/) | GuardDuty organization (Runtime Monitoring, optional EBS malware) |
| [securityhub-org](./securityhub-org/) | Security Hub organization (central configuration) |
| [config-org](./config-org/) | AWS Config org recorder + aggregator |
| [cloudtrail-org](./cloudtrail-org/) | Organization CloudTrail |
| [access-analyzer-org](./access-analyzer-org/) | IAM Access Analyzer (external + unused access) |
| [securitylake](./securitylake/) | Security Lake + subscriber |
| [security-notifications](./security-notifications/) | Security alerting fan-out |
| [incident-response](./incident-response/) | Incident-response scaffolding |
| [firewall-manager-org](./firewall-manager-org/) | Firewall Manager organization |
| [secrets-baseline](./secrets-baseline/) | Secrets Manager baseline |
| [edge-security](./edge-security/) | WAF / edge protection |

## IAM & Identity
| Module | Purpose |
|--------|---------|
| [iam-role](./iam-role/) | Custom IAM role (policy JSON via `jsonencode`) |
| [iam-identity-center](./iam-identity-center/) | IAM Identity Center / SSO permission sets + assignments |

## Networking
| Module | Purpose |
|--------|---------|
| [vpc](./vpc/) | VPC with tiered subnets |
| [vpc-endpoints](./vpc-endpoints/) | Interface / gateway VPC endpoints |
| [transit-gateway](./transit-gateway/) | Transit Gateway with prod/nonprod route-table isolation |
| [network-firewall](./network-firewall/) | AWS Network Firewall |
| [route53-resolver](./route53-resolver/) | Route 53 Resolver endpoints/rules |
| [network-access-analyzer](./network-access-analyzer/) | Network Access Analyzer scopes |
| [ipam](./ipam/) | IP Address Manager |

## Data protection, keys & storage
| Module | Purpose |
|--------|---------|
| [kms-key](./kms-key/) | KMS CMK with rotation + log-service grants |
| [log-archive-bucket](./log-archive-bucket/) | Immutable (Object Lock COMPLIANCE) log-archive S3 bucket |
| [private-ca](./private-ca/) | ACM Private CA |

## Backup
| Module | Purpose |
|--------|---------|
| [backup-vault](./backup-vault/) | Backup vault with Vault Lock (compliance mode) + restore testing |
| [backup-org-policy](./backup-org-policy/) | Organization backup policy |

## Operations
| Module | Purpose |
|--------|---------|
| [systems-manager](./systems-manager/) | Systems Manager (SSM) baseline |

---

**Provider pin:** every AWS module pins `aws = ">= 6.46.0, < 7.0.0"` (deliberate floored pin — see [CLAUDE.md](../../CLAUDE.md) AWS gotchas). **Cross-account modules** declare `configuration_aliases` and cannot be root-`terraform validate`d standalone (CI skips them; covered by `examples/`, composing stages, and `mock_provider` tests).
