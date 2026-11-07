# Runbook: Migrate GCP Hub Connectivity from VPC Peering to NCC

**When to use:** You want environment VPCs to reach the hub through a
[Network Connectivity Center](https://cloud.google.com/network-connectivity/docs/network-connectivity-center/concepts/overview)
(NCC) hub instead of hub-and-spoke VPC peering. NCC removes the peering limits (peering is not
transitive, has a per-network peering cap, and every new spoke means another pair of peerings),
and a STAR hub keeps the same isolation: environment spokes reach the hub VPC but not each other.

**Time:** one PR for the hub, then one PR per environment spoke
**Risk:** Medium to High. Switching a spoke deletes its hub peering. Path (a) costs minutes of
connectivity loss on that spoke; path (b) avoids it at the cost of a temporary HA VPN.
**Prerequisites:**

- **A sandbox proof comes first.** Run path (a) against a sandbox spoke and confirm a re-plan
  shows 0 changes and that the spoke reaches the hub (and its Private Service Access services)
  again. Do that before you adopt `ncc` anywhere else. The default stays `peering`, and
  `scripts/init-landing-zone.sh` does not write `connectivity`.
- `networkconnectivity.googleapis.com` is enabled in the hub project (`shared-hub`) and in every
  environment host project that will become a spoke. Neither gcp-projects nor the network roots
  enable it today.
- The gcp-network-hub apply identity can manage NCC hubs and spokes in the hub project, and each
  gcp-workload-&lt;env&gt; apply identity can manage spokes in its host project (for example
  `roles/networkconnectivity.hubAdmin` and `roles/networkconnectivity.spokeAdmin`). Confirm the
  exact grants in the sandbox.

All applies run in Terraform Cloud and never locally (see
[CLAUDE.md → State & Apply Rules](../../CLAUDE.md#state--apply-rules)).

## How it works

| Setting | Root | Effect |
|---|---|---|
| `gcp.network.ncc_hub.enabled: true` (or `enable_ncc_hub`) | gcp-network-hub | Creates the hub (`<prefix>-ncc-hub`, `policy_mode = PRESET`), the hub VPC as its `center` spoke, and a producer spoke for the hub's Private Service Access peering. Publishes `contract.hub_network.ncc_hub_id` and `ncc_spoke_group`. |
| `gcp.network.ncc_hub.preset_topology` (or `ncc_preset_topology`) | gcp-network-hub | `STAR` (default) or `MESH`. **Immutable:** changing it replaces the hub, which needs every spoke removed first. |
| `gcp.network.connectivity: ncc` | every gcp-workload-&lt;env&gt; | Default connectivity for all environments. |
| `gcp.environments.<env>.network_connectivity` (or `network_connectivity`) | gcp-workload-&lt;env&gt; | Per-environment override; the switch this runbook flips one spoke at a time. |

With `connectivity = ncc`, `modules/gcp/stages/net-spoke` plans no `module.vpc_peering`
instance (the same `for_each` keys come back if you return to `peering`, so there are no
`moved` blocks), and creates `module.ncc_spoke`:

- the environment VPC as a spoke in the hub's `edge` group (`default` on a MESH hub);
- a producer VPC spoke for the environment's Private Service Access peering, in the same group.
  It reads its hub and group from the VPC spoke, so it is created after it, as NCC requires.

The DNS peering zone to the hub DNS anchor stays in both modes: DNS peering is not VPC peering.

STAR pre-creates the `center` and `edge` groups (MESH: `default`). They are referenced as
`<hub id>/groups/<name>` and never managed as resources.

**The constraint that shapes the migration:** NCC rejects a VPC spoke whose VPC is still peered
with another VPC spoke of the hub. The hub VPC can join first, because the environment VPCs it
peers with are not spokes yet. Each environment VPC must lose its hub peering before it can join.
`module.ncc_spoke` declares `depends_on = [module.vpc_peering]`, so in a single apply Terraform
deletes the peering before it creates the spoke.

## Step 0: Create the hub (one PR, no downtime)

1. Set the hub on in `config/landing-zone.yaml`:

   ```yaml
   gcp:
     network:
       ncc_hub:
         enabled: true
         preset_topology: STAR
   ```

2. Plan gcp-network-hub. Expect additions only: `module.hub.module.ncc_hub[0]`,
   `module.hub.module.ncc_hub_spoke[0]` (the center spoke) and its `producer["psa"]` spoke.
   No peering changes.
3. Apply. Peering keeps carrying all traffic, and the contract now carries `ncc_hub_id`.

## Path (a): maintenance window, per spoke (default)

Use this for non-production environments, or wherever a few minutes of loss on one spoke is
acceptable.

1. In a maintenance window, set the environment to NCC:

   ```yaml
   gcp:
     environments:
       dev:
         network_connectivity: ncc
   ```

2. Plan gcp-workload-dev. Expect the hub peering (`module.host.module.vpc_peering["hub-peering"]`,
   both directions) to be destroyed, and `module.host.module.ncc_spoke[0]` with its `psa`
   producer spoke to be created. Nothing else should change.
3. Apply. **Expect minutes of connectivity loss on that spoke** between the peering deletion and
   the spoke becoming `ACTIVE`.
4. The spoke lives in the host project, not the hub project, so NCC may hold it for review. If
   `ncc_spoke_id` shows a spoke in a pending state, the hub admin accepts it:
   `gcloud network-connectivity hubs accept-spoke <hub> --spoke=<spoke id>`.
5. Verify: the spoke reaches hub workloads, and services on Private Service Access (for example
   Cloud SQL) still resolve and connect. Then re-plan gcp-workload-dev: expect 0 changes.

**Rollback:** set `network_connectivity: peering` again and apply. The spoke is destroyed and the
peering re-created under its old key. The rollback has no `depends_on` ordering (the reverse
edge would form a cycle), so if the peering create fails because the spoke is still being
deleted, re-run the apply.

## Path (b): zero downtime, per spoke (production)

Use this for production. A temporary HA VPN carries the traffic while the peering is replaced.

1. Create a temporary HA VPN between the hub VPC and the spoke VPC with
   `modules/gcp/network/vpn` (one gateway on each side, BGP advertising each VPC's ranges).
   While the peering exists, its subnet routes take precedence over the VPN's dynamic routes for
   the same ranges, so peering keeps carrying traffic. Confirm both tunnels are `ESTABLISHED`
   and the BGP sessions are up.
2. Switch the environment to `network_connectivity: ncc`, then plan and apply as in path (a),
   steps 2 to 4. When the peering goes, traffic falls back to the VPN. Once the spoke is
   `ACTIVE`, the subnet routes NCC exchanges take precedence over the VPN's dynamic routes again.
   Confirm that route behaviour in the sandbox before relying on it.
3. Verify as in path (a), step 5, and check that VPN traffic drops to zero.
4. Remove the temporary VPN in a follow-up PR.

## After every spoke has moved

- Set `gcp.network.connectivity: ncc` and drop the per-environment overrides, so new
  environments start on NCC.
- Greenfield landing zones have no peering to migrate. Once the sandbox proof has passed, they
  can start with `ncc_hub.enabled: true` and `connectivity: ncc`.

## Known limits

- The hub's groups are not managed, so there is no Terraform-managed spoke auto-accept list.
  Cross-project spokes may need the manual acceptance in path (a), step 4.
- `export_psc` (Private Service Connect propagation) is off. It is a `stages/net-hub` `ncc`
  setting and is not exposed at the root yet.
