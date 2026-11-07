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
| [network-hub](./network-hub/) | 3 | Hub VPC, DNS hub, VPC-SC, hierarchical firewall (composes `net-hub` + `dns-anchor`) | `envs/gcp/network-hub` |
| [net-hub](./net-hub/) | — | Hub network composition: Shared VPC, NAT, PSA, PSC, hierarchical firewall, hub VPC-SC, HA VPN, Interconnect | `stages/network-hub` |
| [dns-anchor](./dns-anchor/) | — | Workload-free DNS-anchor VPC and the private zones spokes peer to | `stages/network-hub` |
| [net-spoke](./net-spoke/) | — | Per-env spoke network composition: Shared VPC host, NAT, PSA, PSC, hub peering, DNS, Cloud Armor, flow-log export, VPC-SC | `envs/gcp/workload` |
| [workload](./workload/) | — | Per-env application projects (workload factory) | `envs/gcp/workload` / `examples/workloads` |

The AWS landing zone uses the same primitive/stage split under
[`modules/aws/stages/`](../../aws/stages/).
