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
network in place.

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

The tier rules reserve priorities 64000-64999. Any other rule you add to the same policy, such as
the `network/internal-lb` proxy-only rule (`firewall_mode` + `firewall_policy`), must use a
priority outside that block.

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
carried over by `moved` blocks). Under the default `AFTER_CLASSIC_FIREWALL` order, the legacy VPC
rules are evaluated first, so traffic behaviour does not change.

If an internal load balancer uses this VPC, set `firewall_mode = "both"` and
`firewall_policy = <the firewall_policy_name output>` on its `network/internal-lb` module as well.

### 2. Verify with Firewall Insights

Over a representative window (at least one full business cycle), check the following in
**Network Intelligence Center → Firewall Insights** and in the firewall logs:

- The policy rules show hits for the same flows that the legacy allow rules show hits for.
- No legacy allow rule has hits that the matching policy rule would not also have allowed. Check
  in particular for instances that sit outside their tier's subnet but carry a tier tag.
- Health-check probes, IAP SSH, and Cloud Run (direct VPC egress) to Cloud SQL all work.

Fix any gap in the policy rules, for example a missing `api_gateway_source_ranges`, before you go
on.

### 3. Set `policy`

To keep this step separate from the order flip, set `firewall_mode = "policy"` together with
`firewall_policy_enforcement_order = "AFTER_CLASSIC_FIREWALL"`. The plan deletes the 7 legacy VPC
rules (including `deny-all-ingress`) and leaves the policy in place. Do the same on any
`network/internal-lb` modules for this VPC.

### 4. Flip the enforcement order to `BEFORE_CLASSIC_FIREWALL`

Remove the `firewall_policy_enforcement_order` override, or set it to `BEFORE_CLASSIC_FIREWALL`.
The network updates in place, and the policy is now evaluated before any remaining VPC rules (for
example GKE's automatic rules, or `firewall.additional_rules` on `net-spoke`). Re-plan to confirm
that it shows 0 changes.

## Rollback

- **From step 1 or 2:** set `firewall_mode = "legacy"`. The plan removes the policy, the
  association and the policy rules. The legacy rules were never touched.
- **From step 3 or 4:** set `firewall_mode = "both"`. The plan recreates the legacy VPC rules
  under their original names. If you also set the order back to `AFTER_CLASSIC_FIREWALL`, they are
  evaluated first again.

## Notes

- The roots do not expose `firewall_mode` yet: `envs/gcp/workload` and `stages/network-hub` call
  the stages with the default `legacy`. To migrate a deployed network, first wire `firewall_mode`
  (and `firewall_policy_enforcement_order`) through the root that owns it.
- `stages/dns-anchor` composes `tiered-vpc` with the default `legacy` mode.
