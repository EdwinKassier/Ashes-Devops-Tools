# Runbook: AWS CIDR Expansion

**When to use:** A spoke VPC's subnet tier is running out of addresses (< 10% free IPs remaining in a `private` / `isolated` tier), a new workload needs a larger address block than the VPC's primary CIDR can carve, or a Region's IPAM pool is close to fully allocated and needs headroom before the next account is added.

**Time:** 30–90 minutes of hands-on Terraform + TFC work. No workload drain is required for the no-downtime path (Option A); the widen-the-allocation path (Option B) is effectively a new VPC stand-up, so budget for a cutover window.
**Risk:** Medium. Address space is governed centrally by IPAM and shared org-wide over AWS RAM, so an uncoordinated allocation can overlap another account's space or exhaust a Region pool. The primary VPC CIDR is immutable — you **add** blocks, you never resize in place.
**Prerequisites:** IPAM administration lives in the **network** account (`modules/aws/network/ipam`, deployed by the `aws-network` root). You have the region's shared pool id from the `aws-network` root's `ipam_pool_ids` output, permission to plan/apply the affected `aws-workload-<env>` workspace, and — for anything that touches pool sizing or TGW route tables — coordination with the network account owner.

---

## The AWS model: CIDRs come from IPAM, expansion means ADD

Unlike a self-service literal-CIDR world, spoke VPC CIDRs in this landing zone are allocated from **hierarchical IPAM pools** so no two accounts overlap (`modules/aws/network/ipam/main.tf`):

- A single **top-level pool** owns the whole supernet (`var.top_cidr`, default `10.0.0.0/8`) with no locale.
- One **regional pool per enabled Region** (`var.regional_cidrs`, e.g. `eu-west-2 = "10.0.0.0/12"`) is sourced from the top pool and carries the Region locale.
- The regional pools are **RAM-shared organization-wide** to the org ARN (`aws_ram_resource_share` + `aws_ram_principal_association`), so every member account can allocate VPC CIDRs from centrally governed space.

A workload spoke pulls its pool id from the network cross-root contract — `envs/aws/workload/main.tf` reads `data.terraform_remote_state.aws_network.outputs.ipam_pool_ids[var.aws_region]` and passes it to the VPC module as `ipam_pool_id`. The VPC module then allocates its CIDR from that pool (`ipv4_ipam_pool_id` + `ipv4_netmask_length` on `aws_vpc.this`, in `modules/aws/network/vpc/main.tf`).

**AWS does not let you resize a VPC's primary CIDR in place, and IPAM does not let you grow an existing allocation.** So expansion is always additive. There are two shapes:

- **Option A — add a secondary CIDR to the existing VPC** (no downtime). A new block is associated to the live VPC and new subnets are carved from it. Existing subnets, ENIs, and NAT are untouched.
- **Option B — widen the allocation with a larger/new VPC block** (cutover). Because the primary CIDR is immutable, "widening" means requesting a larger block from IPAM into a **new** VPC (or a new secondary block) and migrating workloads onto it.

> **Contrast with GCP.** In the GCP counterpart ([`cidr-expansion.md`](cidr-expansion.md)) changing `ip_cidr_range` plans a destroy-and-recreate of the subnet, and GKE secondary ranges are the no-downtime lever. On AWS the no-downtime lever is a **secondary VPC CIDR association** plus new subnets — subnets are never destroyed to grow the VPC.

---

## Important: know your levers before you plan

Two module-level facts shape every step below:

1. **Subnet layout is deterministic `cidrsubnet()` math, not IPAM.** The VPC module always uses `var.cidr_block` for subnet math even when `ipam_pool_id` drives the VPC allocation (see the header comment in `modules/aws/network/vpc/main.tf`). Each tier in `var.subnets` is `{ newbits, number_offset, public }`, and subnets are carved as `cidrsubnet(cidr_block, newbits, number_offset + az_index)`, one per tier per AZ (`az_count` AZs). So the CIDR you request from IPAM and the `cidr_block` you set **must be the same block**, or the subnet math drifts from reality.

2. **The VPC module does not currently declare a secondary-CIDR resource.** As written, `modules/aws/network/vpc` creates exactly one `aws_vpc` and carves all tiers from its single `cidr_block`. There is **no** `aws_vpc_ipv4_cidr_block_association` in the module today. Option A therefore requires a small module enhancement (shown below) before it can be applied through Terraform — flag this to whoever owns the module. Do not add a secondary block out-of-band in the console against a Terraform-managed VPC; it will drift.

---

## Option A: Add a secondary CIDR (no downtime)

Use this when the VPC's primary block is carved out but the workload just needs another tier or a bigger `private` tier, and you cannot take a cutover window.

### Step 1 — Allocate a non-overlapping block from the Region pool

Confirm the Region's shared pool id and its current utilization before you take anything. Get the pool id from the network root:

```bash
terraform -chdir=envs/aws/network output -json ipam_pool_ids
# → { "eu-west-2": "ipam-pool-0abc..." , ... }
```

Check utilization and existing allocations so the new block does not overlap another account's space:

```bash
# Utilization of the regional pool
aws ec2 get-ipam-pool-cidrs --ipam-pool-id ipam-pool-0abc... \
  --query 'IpamPoolCidrs[].{Cidr:Cidr,State:State}' --output table

# Everything already allocated out of the pool (across the org, RAM-shared)
aws ec2 get-ipam-pool-allocations --ipam-pool-id ipam-pool-0abc... \
  --query 'IpamPoolAllocations[].{Cidr:Cidr,Type:ResourceType,Owner:ResourceOwner}' --output table
```

Pick a block that is inside the regional pool's CIDR (`var.regional_cidrs[<region>]`) and does not appear in the allocations list.

### Step 2 — Teach the VPC module to associate a secondary CIDR

Because `modules/aws/network/vpc` has no secondary-CIDR resource yet, add one. The additive, mock-friendly shape mirrors the existing IPAM-vs-literal switch on the primary:

```hcl
# modules/aws/network/vpc/main.tf — new resource
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  for_each = var.secondary_cidrs

  vpc_id              = aws_vpc.this.id
  ipv4_ipam_pool_id   = each.value.ipam_pool_id != "" ? each.value.ipam_pool_id : null
  ipv4_netmask_length = each.value.ipam_pool_id != "" ? each.value.netmask_length : null
  cidr_block          = each.value.ipam_pool_id == "" ? each.value.cidr_block : null
}
```

```hcl
# modules/aws/network/vpc/variables.tf — new variable
variable "secondary_cidrs" {
  description = "Additional CIDR blocks associated to the VPC after creation. Keyed by a plan-known name; each carries the block for subnet math plus the IPAM pool it is allocated from."
  type = map(object({
    cidr_block     = string
    ipam_pool_id   = optional(string, "")
    netmask_length = optional(number, 16)
  }))
  default = {}
}
```

Subnets in the new range are declared as ordinary tiers, but their `cidrsubnet()` math must operate on the **secondary** block, not the primary `cidr_block`. Add the new tiers with a `base` field (or a parallel `subnets_secondary` map keyed to the association) so the module carves them from `var.secondary_cidrs[<key>].cidr_block` rather than the primary. Keep every `for_each` key a plan-known string so the module still passes its `mock_provider` tests (see the `#tfsec`/mock notes throughout the module).

> This is a genuine module change: run `make docs && make test` on the vpc module and ship it as its own PR (per [CLAUDE.md → Updating an existing module](../../CLAUDE.md)) before the workload apply below.

### Step 3 — Wire the block through the workload stage

The workload stage (`modules/aws/stages/workload/main.tf`) passes `cidr_block`, `subnets`, and `ipam_pool_id` straight through to the VPC module. Add matching `secondary_cidrs` (and the new-tier definitions) as stage variables and forward them, then set them in the `aws-workload-<env>` workspace. The block you set must equal the block you allocated in Step 1.

### Step 4 — Plan and confirm it is additive

```bash
export TF_WORKSPACE=aws-workload-<env>
terraform -chdir=envs/aws/workload plan   # read-only local check; apply via TFC
```

The plan must show `+ aws_vpc_ipv4_cidr_block_association.secondary[...]` and `+ aws_subnet.this[...]` for the new tiers only. It must **not** show any `- destroy` on the existing `aws_vpc`, existing subnets, or the TGW attachment. If it does, stop and re-examine — a change to the primary `cidr_block` or to an existing tier's `newbits`/`number_offset` will re-carve and destroy live subnets.

### Step 5 — Apply via Terraform Cloud

Never apply this root locally. Queue the apply on the `aws-workload-<env>` workspace.

### Step 6 — Add the new subnets to routing

New subnets do not automatically route. Depending on tier:

- **Private/isolated tiers** that reach the hub go through the spoke's TGW attachment. If the new subnets should have the same reachability as existing private subnets, ensure the spoke route table(s) send `0.0.0.0/0` (or the org supernet) to the TGW attachment (`aws_ec2_transit_gateway_vpc_attachment.spoke` in the workload stage).
- **TGW-tier subnets** back the attachment ENIs; you generally do not add a new tgw tier when expanding.

### Step 7 — Propagate the new range across the Transit Gateway

The new CIDR is only reachable from other segments once the hub learns it. TGW segmentation is enforced in the **network** account (`modules/aws/network/transit-gateway`): default association/propagation are disabled, so reachability exists **only** where an explicit propagation exists. A spoke's attachment is associated with exactly one segment route table (`prod` or `nonprod`), and prod↔nonprod is deliberately non-routable (no propagation between them). Adding a secondary CIDR to a spoke that is already attached and associated to its segment table means the hub relearns the attachment's routes automatically via its existing propagation — **no new TGW resource is needed for a secondary block on an already-attached spoke**, provided the Prod/NonProd association is already in place. Confirm the spoke's segment association respects the Prod vs NonProd split before relying on cross-segment reachability (see the note in [Known gaps](#known-gaps--flags) about where spoke associations are wired).

---

## Option B: Widen the allocation (larger block, cutover)

Use this when the workload has outgrown its primary CIDR entirely (e.g. a `/24`-per-tier `/16` needs to become a `/14`) and a secondary block is not enough — for example because you want a single contiguous supernet.

Because the primary CIDR is immutable and IPAM allocations cannot grow, "widening" is a **new, larger allocation into a new VPC** followed by a migration. The steps:

### Step 1 — Confirm the Region pool has room, or widen the pool first

A larger VPC block needs room in the regional pool. Check utilization (Step 1 of Option A). If the regional pool itself is too small, the network account owner widens it by adding a CIDR to the regional pool in `modules/aws/network/ipam` — set/extend `var.regional_cidrs[<region>]` (it must stay inside `var.top_cidr`) and apply the `aws-network` root. This is an additive pool CIDR, not a resize, and is RAM-shared org-wide automatically.

### Step 2 — Request the larger block for a new VPC

Set the workload stage's `vpc_cidr` (and `ipam_pool_id` → the Region pool) to the new, larger block, and size the tiers via `subnets` (`newbits`/`number_offset`). Because the map key of the workload account and the VPC identity change, plan this as a **new VPC** stand-up, not an in-place edit of the live one — the cleanest path is a parallel VPC (new `name`) so you can migrate before deleting the old one.

### Step 3 — Attach the new VPC to the TGW in the correct segment

The new VPC needs its own `aws_ec2_transit_gateway_vpc_attachment.spoke` (created in the workload account) and its association to the **same segment** (Prod or NonProd) the old VPC used. Respect the Prod/NonProd split — a Prod workload must associate to the `prod` route table, never `nonprod`.

### Step 4 — Migrate workloads, then retire the old VPC

Stand up the workload in the new subnets, cut traffic over, verify, then remove the old VPC and its attachment in a follow-up apply. Deallocate the old IPAM allocation so the space returns to the pool (deleting the VPC releases the IPAM allocation automatically; confirm with `get-ipam-pool-allocations`).

---

## IPAM guardrails

Address space is org-wide shared state — treat allocations as a shared resource, not a per-account free-for-all:

- **Always allocate from the Region's shared pool**, never a literal `cidr_block`, for spoke VPCs. Literal CIDRs bypass IPAM's overlap protection. (The module allows literal CIDRs via empty `ipam_pool_id` for the hub/test cases; production spokes should set `ipam_pool_id`.)
- **Check utilization and existing allocations before every allocation** (the two `aws ec2 get-ipam-pool-*` commands above). IPAM will refuse an overlapping allocation, but you want to avoid the failed apply and pick a sensibly-placed block.
- **New blocks must sit inside the regional pool's CIDR** (`var.regional_cidrs[<region>]`), which in turn sits inside `var.top_cidr`. Going outside means widening the pool first (Option B, Step 1).
- **Pools are RAM-shared to the org ARN, not to external principals** (`allow_external_principals = false`). Do not add external-account sharing.
- **Coordinate pool sizing changes with the network account owner** — `regional_cidrs` / `top_cidr` live in the `aws-network` root and affect every account that allocates from that Region.

---

## Interaction with Network Firewall / inspection routing

If the new subnets must have their egress or east-west traffic inspected, remember where inspection is enforced (`modules/aws/stages/network-hub/main.tf`):

- The hub default-routes each segment's `0.0.0.0/0` to the **inspection attachment** (`tgw_routes` → `prod:default` / `nonprod:default` point at `inspection`), so traffic is forced through **AWS Network Firewall** in the inspection VPC before it reaches the centralized NAT in the egress VPC.
- This routing lives on the **TGW segment route tables in the network account**, keyed by segment (Prod/NonProd), not per-subnet. So a **new subnet inside an already-associated spoke inherits inspection automatically** once its spoke route table sends the relevant traffic to the TGW attachment — you do not add a per-subnet inspection route.
- What you must verify: the new subnet's **spoke-side route table** actually points the traffic you want inspected (`0.0.0.0/0`, or specific east-west CIDRs) at the TGW attachment. If a new subnet is meant to be `isolated` (no hub reachability), leave it off the TGW-bound route table entirely.
- Do not attempt to point a new subnet at the inspection VPC directly — inspection is reached only via the TGW segment default route, and appliance-mode symmetric routing on the inspection attachment depends on that path.

---

## Verification

```bash
# 1. Secondary CIDR is associated to the live VPC (Option A)
aws ec2 describe-vpcs --vpc-ids <vpc-id> \
  --query 'Vpcs[0].CidrBlockAssociationSet[].{Cidr:CidrBlock,State:CidrBlockState.State}' \
  --output table
# expect the new block in state "associated"

# 2. New subnets exist in the expected tiers/AZs
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'Subnets[].{Cidr:CidrBlock,AZ:AvailabilityZone,Tier:Tags[?Key==`Tier`]|[0].Value}' \
  --output table

# 3. IPAM shows the allocation and the pool is not over-committed
aws ec2 get-ipam-pool-allocations --ipam-pool-id <region-pool-id> \
  --query 'IpamPoolAllocations[?ResourceId==`<vpc-id>`]' --output table

# 4. The spoke is attached to the TGW and associated to the right segment
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'TransitGatewayVpcAttachments[].{Att:TransitGatewayAttachmentId,State:State}' \
  --output table
# then confirm its route-table association is prod XOR nonprod (network account)

# 5. Reachability test from an instance in a new subnet (inspection path)
#    From a host in the new subnet, egress should traverse the firewall then NAT.
```

Terraform-side confirmation:

```bash
export TF_WORKSPACE=aws-workload-<env>
terraform -chdir=envs/aws/workload plan   # must be a clean no-op after apply
```

A clean no-op plan is the final proof: the associated secondary CIDR, its subnets, and the TGW attachment all match state, with nothing pending.

---

## Known gaps / flags

- **Secondary-CIDR resource is not in the module yet.** `modules/aws/network/vpc` has no `aws_vpc_ipv4_cidr_block_association`; Option A requires the module enhancement in Step 2 (shipped as its own PR with `make docs && make test`). Until then the only code-native expansion is Option B (a larger/new VPC block).
- **Spoke → Prod/NonProd route-table association is not visibly wired in the composed stages.** The workload stage creates the spoke attachment with both default-route-table flags `false` and states association/propagation are "managed in the network account", but the `network-hub` stage's `attachments` map only contains the `inspection` and `egress` attachments — it does not enumerate per-workload spoke attachments. Confirm with the network account owner exactly where each spoke's `prod`/`nonprod` route-table association is created before relying on cross-segment reachability or inspection for a newly-expanded spoke.
- **No `aws_vpc_ipam_pool_cidr_allocation` reservation resource.** The module provisions pool CIDRs (`aws_vpc_ipam_pool_cidr`) but allocations happen implicitly when a VPC requests from the pool. Utilization and overlap must be checked with the AWS CLI (above), not from Terraform state.

---

## See also

- [CIDR Expansion (GCP)](cidr-expansion.md) — the GCP counterpart (secondary GKE ranges vs. subnet destroy-and-recreate).
- [AWS Landing Zone](../architecture/aws-landing-zone.md) — account/OU model, network topology, and the two-tier IPAM design.
- [Add an AWS Account / Environment](aws-add-account.md) — standing up a new spoke, where its first CIDR is allocated.
