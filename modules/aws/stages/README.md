# AWS Stages

Orchestration wrappers that compose the primitives under [`modules/aws/`](../)
into deployable layers. Each stage is invoked from the matching root under
[`envs/aws/`](../../../envs/aws/) and follows the AWS SRA layering.

| Stage | Composes | Invoked from | Apply order |
|-------|----------|--------------|:-----------:|
| [organization](./organization/) | `organization`, `organization-policy`, `iam-organizations-features`, `account`, `cost-governance` | `envs/aws/organization` | 1 |
| [security](./security/) | delegated-admin + GuardDuty/Security Hub/Config/CloudTrail/Access Analyzer/Security Lake/Macie/Inspector, `kms-key`, `log-archive-bucket` | `envs/aws/security` | 2 |
| [network-hub](./network-hub/) | `transit-gateway`, `ipam`, `network-firewall`, `route53-resolver`, `vpc-endpoints` | `envs/aws/network` | 3 |
| [shared-services](./shared-services/) | shared platform services (SSM, private CA, secrets) | `envs/aws/shared-services` | 4 |
| [backup](./backup/) | `backup-vault`, `backup-org-policy` | `envs/aws/backup` | 5 |
| [workload](./workload/) | per-env workload account infrastructure | `envs/aws/workload` (`TF_WORKSPACE=aws-workload-<env>`) | 6 |

Ordering is enforced by apply order + remote-state reads, not cross-root
`depends_on`. See the [AWS bootstrap runbook](../../../docs/runbooks/aws-bootstrap.md).

The GCP landing zone uses the same primitive/stage split under
[`modules/gcp/stages/`](../../gcp/stages/).
