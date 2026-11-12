# Global CIDR Allocation Plan

One source of truth for IP space across both clouds (audit L2). Today AWS and GCP
are network islands with no cross-cloud connectivity, so their ranges can in
principle overlap. This plan allocates **non-overlapping** space anyway, so that
adding the already-scaffolded VPN modules (`modules/aws/network/vpn`,
`modules/gcp/network/vpn`) to interconnect the clouds later cannot cause a
collision. Keep this document updated whenever a new environment or region is
added.

## Top-level split

The private `10.0.0.0/8` space is divided by cloud, with a wide gap reserved
between them for growth:

| Range | Owner | Notes |
|---|---|---|
| `10.0.0.0/12` (`10.0.0.0`–`10.15.255.255`) | **GCP** | Hub, DNS, and per-environment host VPCs. |
| `10.16.0.0/12` – `10.63.0.0/12` | **Reserved** | Unused buffer; do not allocate without updating this plan. |
| `10.64.0.0/10` (`10.64.0.0`–`10.127.255.255`) | **AWS** | Supernet managed by IPAM in `envs/aws/network`. |
| `172.16.0.0/12`, `192.168.0.0/16` | **Reserved** | On-prem / partner / SaaS peering only. |

## GCP (`10.0.0.0/12`)

Defined by the `environments` map (`cidr_block` per env) and the hub CIDRs on the
`gcp-network-hub` root. Current allocation:

| Purpose | CIDR | Set in |
|---|---|---|
| Hub VPC (`shared-hub`) | `10.0.0.0/16` | `hub_vpc_cidr_block` (gcp-network-hub) |
| DNS hub VPC (`shared-dns`) | `10.1.0.0/16` | `dns_hub_vpc_cidr_block` (gcp-network-hub) |
| `10.2.0.0/16` – `10.9.0.0/16` | reserved (shared/future) | — |
| Per-env host VPC (dev) | `10.10.0.0/16` | `environments["dev"].cidr_block` |
| Per-env host VPC (uat) | `10.11.0.0/16` | `environments["uat"].cidr_block` |
| Per-env host VPC (prod) | `10.12.0.0/16` | `environments["prod"].cidr_block` |
| New environments | `10.13.0.0/16` onward | `environments[<new>].cidr_block` |
| PSC endpoint for Google APIs (hub) | `10.0.255.254` (second-to-last address of the hub CIDR) | `gcp.network.private_service_connect.address` (gcp-network-hub) |
| PSC endpoint for Google APIs (each environment) | second-to-last address of the environment CIDR, for example `10.10.255.254` | `gcp.environments.<env>.private_service_connect.address` |

Private Service Connect endpoints for Google APIs need one explicit internal IPv4
address per VPC. Google's rules for that address (from
[About accessing Google APIs through endpoints](https://docs.cloud.google.com/vpc/docs/about-accessing-google-apis-endpoints),
checked 2026-11-12): it "can't be within a primary or secondary IP address range of
any subnet in the VPC network" or of a network connected by VPC Network Peering,
and it must be a single IPv4 address. Endpoints are not reachable from peered VPC
networks, so each VPC gets its own endpoint. The default is the second-to-last
address of the VPC's own block. The default subnet layout uses only the first 48
`/24` blocks of a `/16`, so that address is free, and it is outside every other
VPC's block. `net-hub` and `net-spoke` fail the plan when the address is inside a
subnet range of their VPC. If you place a subnet or secondary range at the top of
the block, set `private_service_connect.address` to a free address first.

Rule: each GCP environment gets one `/16`, assigned sequentially from `10.10.0.0/16`.
The hub and DNS VPCs must not overlap any env CIDR. tfc-admin enforces this: its
plan fails when two ranges in `config/landing-zone.yaml` overlap (see
[Enforcement](#enforcement)).

## AWS (`10.64.0.0/10`)

Managed by the IPAM pool hierarchy in `envs/aws/network` (`modules/aws/network/ipam`).
IPAM allocates each spoke VPC a CIDR from the regional pool, so per-VPC ranges are
not hand-assigned. Keep the top-level IPAM supernet inside `10.64.0.0/10` and
record any additional regional pools here.
The inspection and egress VPCs keep their static CIDRs by default. aws-network
reserves each static hub block that lies inside the regional pool
(`hub_static_ipam_allocations` in `modules/aws/stages/network-hub`), and a hub
VPC created from the pool is its own allocation, so IPAM never allocates a hub
range to a spoke. A hub CIDR that only partly overlaps the regional pool fails
the aws-network plan.

| Purpose | Default CIDR | Set in (`config/landing-zone.yaml`) |
|---|---|---|
| IPAM supernet | `10.64.0.0/10` | `aws.network.top_cidr` |
| Regional pool (primary region) | `10.64.0.0/12` | `aws.network.regional_cidrs` |
| Inspection VPC | `10.64.0.0/16` | `aws.network.inspection_cidr` |
| Egress VPC | `10.65.0.0/16` | `aws.network.egress_cidr` |
| Workload VPC (dev, example) | `10.72.0.0/16` | `aws.workload_environments.<env>.vpc_cidr` (built-in default `10.72.0.0/16`) |
| Workload VPC (prod, example) | `10.73.0.0/16` | `aws.workload_environments.<env>.vpc_cidr` |

## Capacity

| Space | Unit | Fits | Growth path |
|---|---|---|---|
| GCP environments (`10.10.0.0/16` to `10.15.0.0/16`) | one `/16` per environment | 6 environments | Take more space from the Reserved buffer (`10.16.0.0/12` and up) after you update this plan. `10.2.0.0/16` to `10.9.0.0/16` is marked reserved for shared use, so do not hand it to environments without changing this plan. |
| AWS regional pool (`10.64.0.0/12`) | one `/16` per VPC; the default inspection and egress VPCs use two | 14 workloads per region | `aws.network.regional_additional_cidrs` adds a second `/12` to the pool, for example `10.80.0.0/12` (see [aws-cidr-expansion.md](../runbooks/aws-cidr-expansion.md#region-pool-is-full-add-awsnetworkregional_additional_cidrs)). |

## GKE secondary ranges

GKE Pods and Services use secondary ranges on the private subnet. They are documented here, not provisioned: see [Known gaps](../known-gaps.md).
This plan proposes `100.64.0.0/10` (RFC 6598 shared address space) for them, so they never use the `/16` of an environment.
Nothing in this repository uses `100.64.0.0/10` today. The GCP, Reserved and AWS blocks above are all inside `10.0.0.0/8`.
The GKE control plane keeps `172.16.0.0/28` and the VPN uses `169.254.0.0/16` link-local addresses. Cloud NAT uses external addresses, not a VPC range.

| Environment index `i` (sorted key order, 0 to 14) | Pods (`/14`) | Services (`/20`) |
|---|---|---|
| `i` | `cidrsubnet("100.64.0.0/10", 4, i)` | `cidrsubnet("100.127.0.0/16", 4, i)` |

The Services block `100.127.0.0/16` sits inside the last Pod `/14` (`100.124.0.0/14`, `i = 15`), so use indexes 0 to 14 only.
Every secondary range must be unique across the VPC networks that peer or connect, so give each environment its own pair.
Set the ranges on the environment's private subnet through `secondary_ranges` (see
[cidr-expansion.md](../runbooks/cidr-expansion.md)), and name them in
`app_platform.gke.cluster_secondary_range_name` and `services_secondary_range_name`.

What is confirmed and what is not:

- Confirmed: the Google Cloud VPC documentation lists `100.64.0.0/10` ("Shared address space [RFC 6598]") as a valid subnet range, usable for primary and secondary ranges ([VPC subnets](https://docs.cloud.google.com/vpc/docs/subnets)).
- Not confirmed: that GKE Autopilot accepts `100.64.0.0/10` for Pods. The GKE page on Pod and Service ranges ([IP ranges for alias IPs](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/alias-ips)) names only RFC 1918 and privately used public ranges and does not mention this block. Test one cluster in a sandbox before you rely on it, and use an RFC 1918 range from the Reserved buffer if it fails.
- Not checked: how Pod traffic to on-premises is source-translated. If the on-premises network already uses `100.64.0.0/10`, or does not route it, choose another range.
- Autopilot clusters on GKE 1.27 and later take Service addresses from a Google-managed range by default, so the Services secondary range is optional.

## Enforcement

tfc-admin reads the whole config file and fails its plan when:

- any two of the GCP hub, DNS hub and `gcp.environments.*.cidr_block` ranges overlap;
- any of those overlaps `aws.network.top_cidr` or a fixed AWS VPC range (inspection, egress, a set `vpc_cidr`);
- two fixed AWS VPC ranges overlap, where a workload without `vpc_cidr` counts as
  `10.72.0.0/16`, so two such workloads overlap;
- a fixed AWS VPC range is outside `aws.network.top_cidr`; or
- an `aws.workload_environments.*.vpc_cidr` is outside every CIDR of the home-region regional pool
  (`aws.network.regional_cidrs.<org.regions.aws>`, default `10.64.0.0/12`, plus
  `aws.network.regional_additional_cidrs.<org.regions.aws>`). The static hub
  ranges may sit outside the pool; they stay in the overlap checks above; or
- an `aws.network.regional_additional_cidrs` entry is outside `aws.network.top_cidr` or overlaps another pool CIDR.

The check reads only the config file. A CIDR set as an explicit TFC variable on a
network workspace is not checked, so keep CIDRs in the config file.

## Before enabling cross-cloud VPN

1. Confirm the AWS IPAM supernet and every GCP env `/16` fall in their allocated
   blocks above with no overlap.
2. Allocate the VPN/transit tunnel ranges from the Reserved buffer, not from a
   cloud's production space.
3. Update this plan and the two landing-zone docs in the same change.
