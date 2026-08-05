# GCP Stages

Orchestration wrappers that compose the primitives under [`modules/gcp/`](../)
into the staged landing zone (aligned with [Cloud Foundation Fabric
FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric)). The full
staged-deployment diagram is in the [top-level modules README](../../README.md).

| Stage | # | Purpose | Invoked from |
|-------|:-:|---------|--------------|
| [bootstrap](./bootstrap/) | 0 | Admin project, Terraform SA, Workload Identity Federation | `envs/gcp/organization` |
| [organization](./organization/) | 1 | Folders, IAM, org policies, tags, audit logs, SCC | `envs/gcp/organization` |
| [projects](./projects/) | 2 | Platform projects (host/spoke/DNS/hub) | `envs/gcp/organization` |
| [network-hub](./network-hub/) | 3 | Hub VPC, DNS hub, VPC-SC, hierarchical firewall | `envs/gcp/organization` |
| [workload](./workload/) | — | Per-env application projects (workload factory) | `envs/gcp/workload` / `examples/workloads` |
| [host](./host/) | — | Per-env Shared VPC host-project network — composes ~30 `network/` + `governance/` primitives (VPC, subnets, firewalls, NAT, DNS, VPN, interconnect, VPC-SC, Cloud Armor, …) | `envs/gcp/workload` |

The AWS landing zone uses the same primitive/stage split under
[`modules/aws/stages/`](../../aws/stages/).
