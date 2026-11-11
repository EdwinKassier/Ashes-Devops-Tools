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

Rule: each GCP environment gets one `/16`, assigned sequentially from `10.10.0.0/16`.
The hub and DNS VPCs must not overlap any env CIDR. tfc-admin enforces this: its
plan fails when two ranges in `config/landing-zone.yaml` overlap (see
[Enforcement](#enforcement)).

## AWS (`10.64.0.0/10`)

Managed by the IPAM pool hierarchy in `envs/aws/network` (`modules/aws/network/ipam`).
IPAM allocates each spoke VPC a CIDR from the regional pool, so per-VPC ranges are
not hand-assigned. Keep the top-level IPAM supernet inside `10.64.0.0/10` and
record any additional regional pools here.

| Purpose | Default CIDR | Set in (`config/landing-zone.yaml`) |
|---|---|---|
| IPAM supernet | `10.64.0.0/10` | `aws.network.top_cidr` |
| Regional pool (primary region) | `10.64.0.0/12` | `aws.network.regional_cidrs` |
| Inspection VPC | `10.64.0.0/16` | `aws.network.inspection_cidr` |
| Egress VPC | `10.65.0.0/16` | `aws.network.egress_cidr` |
| Workload VPC (dev, example) | `10.72.0.0/16` | `aws.workload_environments.<env>.vpc_cidr` (built-in default `10.72.0.0/16`) |
| Workload VPC (prod, example) | `10.73.0.0/16` | `aws.workload_environments.<env>.vpc_cidr` |

## Enforcement

tfc-admin reads the whole config file and fails its plan when:

- any two of the GCP hub, DNS hub and `gcp.environments.*.cidr_block` ranges overlap;
- any of those overlaps `aws.network.top_cidr` or a fixed AWS VPC range (inspection, egress, a set `vpc_cidr`);
- two fixed AWS VPC ranges overlap; or
- a fixed AWS VPC range is outside `aws.network.top_cidr`.

The check reads only the config file. A CIDR set as an explicit TFC variable on a
network workspace is not checked, so keep CIDRs in the config file.

## Before enabling cross-cloud VPN

1. Confirm the AWS IPAM supernet and every GCP env `/16` fall in their allocated
   blocks above with no overlap.
2. Allocate the VPN/transit tunnel ranges from the Reserved buffer, not from a
   cloud's production space.
3. Update this plan and the two landing-zone docs in the same change.
