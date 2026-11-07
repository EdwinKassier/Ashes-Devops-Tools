# Runbook: Migrate GCP Tier Firewalls to a Network Firewall Policy

**When to use:** You want a tiered VPC's baseline firewall to select tiers by **subnet CIDR**
instead of **network tag**. With tag-based VPC rules, any principal that can call
`compute.instances.setTags` can tag an instance `database` and move it into the database tier.
A network firewall policy keyed on subnet CIDRs removes that escalation path.

**Time:** three PRs, with a verification window between the first and the second
**Risk:** Medium. The migration is additive until step 3, which deletes the legacy VPC rules.
**Prerequisites:**

- The VPC is built by `modules/gcp/network/tiered-vpc`, either directly or through
  `modules/gcp/stages/net-spoke` or `modules/gcp/stages/net-hub`.
- Firewall rule logging is on (`firewall.enable_logging`, the default), so Firewall Insights has
  data to show.
- **A sandbox proof comes first.** Run this whole runbook against a sandbox spoke and confirm that
  a re-plan shows 0 changes and that Cloud Run can still reach Cloud SQL. Do that before you adopt
  `policy` anywhere else. The default stays `legacy`, and `scripts/init-landing-zone.sh` does not
  write `firewall_mode`.

All applies run in Terraform Cloud and never locally (see
[CLAUDE.md → State & Apply Rules](../../CLAUDE.md#state--apply-rules)).

## How the modes work

| `firewall_mode` | Tag-based VPC rules | Network firewall policy | Default enforcement order |
|---|---|---|---|
| `legacy` (default) | all 7 | none | unset (API default `AFTER_CLASSIC_FIREWALL`) |
| `both` | all 7 | 1 policy, 1 association, tier rules | unset (`AFTER_CLASSIC_FIREWALL`) |
| `policy` | none | 1 policy, 1 association, tier rules | `BEFORE_CLASSIC_FIREWALL` |

`firewall_policy_enforcement_order` overrides the derived order in any mode. It updates the
network in place. In `policy` mode with the override unset, a `check` block raises a plan warning,
because Terraform cannot tell a greenfield network from one that is moving off `both` (see the
warning in step 3). Setting the order explicitly silences it.

The policy is named `<network>-tier-policy`, and a VPC accepts only one global network firewall
policy association. Its rules mirror the legacy rules:

| Policy rule | Priority | Source | Destination / target |
|---|---|---|---|
| `apigateway-to-public` (only when `firewall.api_gateway_source_ranges` is set) | 64000 | `api_gateway_source_ranges` | public subnet CIDRs, tcp 443/80 |
| `public-to-compute` | 64010 | public subnet CIDRs | private subnet CIDRs, `compute_tier_ports` |
| `compute-to-database` | 64020 | private subnet CIDRs | database subnet CIDRs, `database_ports` |
| `iap-ssh-rdp` (when `enable_iap_access`) | 64030 | `35.235.240.0/20` | tcp 22/3389 |
| `health-checks` | 64040 | `35.191.0.0/16`, `130.211.0.0/22` | all tcp |
| `database-deny-egress` (egress deny) | 64900 | database subnet CIDRs | `0.0.0.0/0` (optional `database_egress_target_service_accounts`) |

The tier rules reserve priorities 64000-64999. Any other rule you add to the same policy must use
a priority outside that block, and priorities must be unique within the policy. The
`network/internal-lb` proxy-only rule (`firewall_mode` + `firewall_policy`) derives a stable
priority in 1000-63999 from a hash of the ILB name, so several ILBs on one VPC normally get distinct
priorities. If two names collide, the apply fails on the duplicate priority: set
`firewall_policy_rule_priority` explicitly on one of them. The `firewall_policy_rule_priority`
output shows the value in use.

The policy has **no trailing deny-all**. Traffic that no policy rule matches goes to the next
stage: the VPC rules, then the implied deny-ingress. This keeps GKE's automatically created VPC
firewall rules working. In `policy` mode the legacy `<network>-deny-all-ingress` rule is removed,
and the implied deny-ingress takes its place.

Network firewall policy rules cannot select network tags. Ingress rules therefore pick their target
tier with destination ranges, not target tags, and `target_service_accounts` is used only on egress.

## Steps

### 1. Set `both`

Set `firewall_mode = "both"` on the tiered VPC. The plan adds the policy, the association and the
tier rules, and changes nothing else: the 7 legacy rule module calls keep their addresses (`[0]`,
carried over by `moved` blocks). The order stays at the default `AFTER_CLASSIC_FIREWALL`, so the
legacy VPC rules are evaluated first.

If an internal load balancer uses this VPC, set `firewall_mode = "both"` and
`firewall_policy = <the firewall_policy_name output>` on its `network/internal-lb` module as well.

What `both` does and does not change:

- **Ingress: no change, and the policy's ingress rules never decide.** Under
  `AFTER_CLASSIC_FIREWALL` every ingress flow is decided by the VPC rules first: the legacy allows
  match the tagged flows, and the legacy `<network>-deny-all-ingress` (priority 65535, source
  `0.0.0.0/0`) terminates every other flow. No ingress flow ever reaches the policy, so the
  policy's ingress allow rules show **0 hits** in Firewall Insights and the firewall logs. That
  proves nothing about them.
- **Egress: a behaviour change.** The legacy VPC rules have no egress allow, and the legacy egress
  deny matches only instances tagged `database`. Egress from any other instance falls through to
  the policy. There, `database-deny-egress` matches by **source subnet**, so instances in the
  database subnets that do **not** carry the `database` tag are newly blocked from all egress as
  soon as `both` applies. Run the tier audit in step 2 **before** step 1 and move or re-tag any such
  instance first.

### 2. Verify

Firewall Insights cannot verify the policy's ingress rules in `both` mode (see step 1). Verify
with configuration analysis instead.

**a. Audit tags against subnet tiers.** The policy selects tiers by subnet and the legacy rules by
tag, so any instance whose tags don't match its subnet's tier changes behaviour at step 3 (ingress),
or already at step 1 (database egress). List each instance with its subnet and tags:

```sh
gcloud compute instances list --project=<host-or-service-project> \
  --filter='networkInterfaces[].network ~ /networks/<network>$' \
  --format='table(name, zone.basename(), networkInterfaces[0].subnetwork.basename():label=SUBNET, tags.items.list():label=TAGS)'
```

Then list the mismatches directly. Each command must return nothing:

```sh
# tier tag set, but the instance is outside that tier's subnets
gcloud compute instances list --project=<project> --filter='tags.items=database AND NOT networkInterfaces[0].subnetwork ~ -db-'
gcloud compute instances list --project=<project> --filter='tags.items=compute  AND NOT networkInterfaces[0].subnetwork ~ -private-'
gcloud compute instances list --project=<project> --filter='tags.items=public   AND NOT networkInterfaces[0].subnetwork ~ -public-'
# instance in a tier subnet but missing that tier's tag
gcloud compute instances list --project=<project> --filter='networkInterfaces[0].subnetwork ~ -db- AND NOT tags.items=database'
gcloud compute instances list --project=<project> --filter='networkInterfaces[0].subnetwork ~ -private- AND NOT tags.items=compute'
gcloud compute instances list --project=<project> --filter='networkInterfaces[0].subnetwork ~ -public- AND NOT tags.items=public'
```

On a Shared VPC, run these in every service project attached to the host. Resolve each mismatch by
moving the instance to the right subnet or by accepting the new behaviour explicitly. GKE nodes and
other managed instances are covered by their own automatic VPC rules.

**b. Baseline the critical flows with Connectivity Tests.** In **Network Intelligence Center →
Connectivity Tests**, or with `gcloud network-management connectivity-tests create`, create one test
per critical flow:

- public → compute on `compute_tier_ports`
- compute → database on `database_ports`
- Cloud Run (direct VPC egress) → Cloud SQL
- health-check probes → backends
- IAP → SSH
- database-tier egress, expected to be **denied**

Record the results and keep the tests: they are re-run after step 3. Firewall Insights in `both`
mode is useful only for the egress side, where `database-deny-egress` hits show which
database-subnet instances it now blocks.

Fix any gap in the policy rules, for example a missing `api_gateway_source_ranges`, before you go
on.

### 3. Set `policy` (policy ingress decides for the first time)

To keep this step separate from the order flip, set `firewall_mode = "policy"` together with
`firewall_policy_enforcement_order = "AFTER_CLASSIC_FIREWALL"`. The plan deletes the 7 legacy VPC
rules (including `deny-all-ingress`) and leaves the policy in place. Do the same on any
`network/internal-lb` modules for this VPC.

**This is the step where the policy's ingress rules first decide traffic.** Once the legacy rules
are gone, ingress reaches the policy, and anything it does not allow falls through to the implied
deny. Re-run every Connectivity Test from step 2 straight after the apply. If any result differs
from the baseline, roll back to `both` (see Rollback).

> **Warning: do not leave `firewall_policy_enforcement_order` unset in this step.** With
> `firewall_mode = "policy"` and no override, the order is derived as `BEFORE_CLASSIC_FIREWALL`, so
> a network moving from `both` would delete the legacy rules **and** flip the order in the same
> apply. The plan shows the `firewall_policy_enforcement_order_explicit` check warning when the
> override is unset.

### 4. Flip the enforcement order to `BEFORE_CLASSIC_FIREWALL`

Set `firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"`. Set it explicitly rather than
removing the override: the value is the same, but explicit keeps the check silent. The network
updates in place, and the policy is now evaluated before any remaining VPC rules (for example GKE's
automatic rules, or `firewall.additional_rules` on `net-spoke`). Re-run the Connectivity Tests,
then re-plan to confirm that it shows 0 changes.

## Rollback

- **From step 1 or 2:** set `firewall_mode = "legacy"`. The plan removes the policy, the
  association and the policy rules. The legacy rules were never touched.
- **From step 3 or 4:** set `firewall_mode = "both"` and remove the
  `firewall_policy_enforcement_order` override. The plan recreates the legacy VPC rules under their
  original names. With no override, `both` restores `AFTER_CLASSIC_FIREWALL` automatically
  (the provider default), so the legacy rules are evaluated first again. Only an explicit
  `BEFORE_CLASSIC_FIREWALL` override left in place would keep the policy first.

## Notes

- The roots do not expose `firewall_mode` yet: `envs/gcp/workload` and `stages/network-hub` call
  the stages with the default `legacy`. To migrate a deployed network, first wire `firewall_mode`
  (and `firewall_policy_enforcement_order`) through the root that owns it.
- `stages/dns-anchor` composes `tiered-vpc` with the default `legacy` mode.
