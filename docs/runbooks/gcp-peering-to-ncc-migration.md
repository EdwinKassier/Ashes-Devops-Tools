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
- The NCC prerequisites are in place. They are all driven by the same config keys, so step 0
  sets them up, and the [pre-flight](#pre-flight-before-every-spoke-window) checks them:
  - the `networkconnectivity.googleapis.com` API on the hub project (`shared-hub`) and on every
    environment host project (gcp-projects);
  - the folder-scoped NCC roles (gcp-bootstrap, then gcp-organization's delegation allow-list,
    then gcp-projects' grants). The network-hub SAs get `roles/networkconnectivity.hubAdmin` and
    `spokeAdmin` on the shared folder. Each workload SA gets `spokeAdmin` on its own environment
    folder. The plan SAs get `hubViewer`;
  - the spoke group's auto-accept list (gcp-network-hub), which holds every environment host
    project.

**Why the pre-flight matters:** in one apply, Terraform deletes the peering *before* it creates
the spoke. Any NCC prerequisite that is still missing fails the spoke create **after** the
peering is gone, and the spoke stays disconnected until you fix it or roll back.

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
`<hub id>/groups/<name>`. The one exception is the spoke group (`edge`, or `default` on MESH).
gcp-network-hub adopts it by name (`google_network_connectivity_group`) to set its auto-accept
list to the environment host projects. This is needed because spokes are created in the host
projects, not the hub project, and NCC otherwise holds a cross-project spoke for review. The
provider only accepts the service-created group names, and its create updates the existing
group, so you don't need to import anything. If a plan nonetheless reports the group as already
existing, import it:
`terraform import 'module.network_hub.module.hub.module.ncc_hub[0].google_network_connectivity_group.spoke[0]' projects/<hub project>/locations/global/hubs/<hub>/groups/edge`
(one-off, from a TFC-connected CLI run).

**The constraint that shapes the migration:** NCC rejects a VPC spoke whose VPC is still peered
with another VPC spoke of the hub. The hub VPC can join first, because the environment VPCs it
peers with are not spokes yet. Each environment VPC must lose its hub peering before it can join.
`module.ncc_spoke` declares `depends_on = [module.vpc_peering]`, so in a single apply Terraform
deletes the peering before it creates the spoke.

## Step 0: Create the hub and its prerequisites (one PR, no downtime)

1. Set the hub on in `config/landing-zone.yaml`:

   ```yaml
   gcp:
     network:
       ncc_hub:
         enabled: true
         preset_topology: STAR
   ```

2. Apply the control plane in order. Each layer reads the one before it, so each needs a fresh
   apply:
   1. **gcp-bootstrap:** adds the NCC roles to `network_folder_roles` / `workload_folder_roles`
      and to the delegation allow-lists. This is additions only.
   2. **gcp-organization:** widens the per-folder delegated folderIamAdmin condition to the new
      roles. This is an in-place update.
   3. **gcp-projects:** enables `networkconnectivity.googleapis.com` on `shared-hub` and every
      `<env>-host` project, and grants the NCC folder roles. This is additions only.
3. Plan gcp-network-hub. Expect additions only:
   - `module.hub.module.ncc_hub[0]` (the hub, plus `google_network_connectivity_group.spoke[0]`
     with the auto-accept list);
   - `module.hub.module.ncc_hub_spoke[0]` (the center spoke) and its `producer["psa"]` spoke.

   There should be no peering changes.
4. Apply. Peering keeps carrying all traffic, and the contract now carries `ncc_hub_id`.

## Pre-flight (before every spoke window)

Run these before each spoke's maintenance window. Fix any failure first. Every check here is
something that would otherwise fail *after* the peering is deleted.

```sh
HUB_PROJECT=<shared-hub project id>; HOST_PROJECT=<env host project id>
HOST_NUMBER=$(gcloud projects describe "$HOST_PROJECT" --format='value(projectNumber)')
HUB=$(terraform output -json contract | jq -r .hub_network.ncc_hub_id)   # in gcp-network-hub

# 1. API enabled on both projects (expect one line each).
gcloud services list --enabled --project="$HUB_PROJECT"  --filter='config.name=networkconnectivity.googleapis.com'
gcloud services list --enabled --project="$HOST_PROJECT" --filter='config.name=networkconnectivity.googleapis.com'

# 2. The environment's workload apply SA holds spokeAdmin on its environment folder.
gcloud resource-manager folders get-iam-policy <env folder id> \
  --flatten=bindings --filter='bindings.role=roles/networkconnectivity.spokeAdmin' \
  --format='value(bindings.members)'        # expect serviceAccount:<prefix>-wl-<env>-apply@...

# 3. The hub and the center spoke are ACTIVE.
gcloud network-connectivity hubs describe "$HUB" --format='value(state)'
gcloud network-connectivity hubs list-spokes "$HUB" --format='table(name,group,state)'

# 4. The host project is on the spoke group's auto-accept list (no manual accept needed).
gcloud network-connectivity hubs groups describe edge --hub="$HUB" \
  --format='value(autoAccept.autoAcceptProjects)' | tr ';' '\n' | grep -x "$HOST_NUMBER"
```

Also have the rollback PR (`network_connectivity: peering`) ready before you start.

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
4. Check the spoke state (`gcloud network-connectivity hubs list-spokes <hub>`). The pre-flight
   auto-accept check should make this a no-op. If the spoke is nevertheless held for review,
   the hub admin accepts it: `gcloud network-connectivity hubs accept-spoke <hub>
   --spoke=<spoke id>`. The PSA producer spoke may fail to create until its consumer VPC spoke
   is accepted. If it does, re-run the apply after the accept.
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

   > **WARNING: the route precedence in this step is unverified.** That NCC subnet routes win
   > over the VPN's dynamic routes (and that the VPN carries traffic in the gap) is not yet
   > proven in this landing zone. Prove it in the sandbox, by watching `gcloud compute routes
   > list` and the effective routes on a VM, before you use path (b) for production. Until
   > then, path (b) is not zero-downtime.
3. Verify as in path (a), step 5, and check that VPN traffic drops to zero.
4. Remove the temporary VPN in a follow-up PR.

## After every spoke has moved

- Set `gcp.network.connectivity: ncc` and drop the per-environment overrides, so new
  environments start on NCC.
- Greenfield landing zones have no peering to migrate. Once the sandbox proof has passed, they
  can start with `ncc_hub.enabled: true` and `connectivity: ncc`.

## Known limits

- Only the spoke group (`edge` / `default`) is managed, for its auto-accept list. It is
  destroyed only with the hub, which a topology change also requires. Whether the API accepts
  deleting a service-created group is unverified. If a destroy fails there, stop managing it with
  `terraform state rm` on the group address before you retry.
- `export_psc` (Private Service Connect propagation) is off. It is a `stages/net-hub` `ncc`
  setting and is not exposed at the root yet.
