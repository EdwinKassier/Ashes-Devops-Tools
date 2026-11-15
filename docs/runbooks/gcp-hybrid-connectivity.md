# GCP hybrid connectivity: routes, DNS and HA VPN key rotation

Applies to the hub HA VPN (`gcp.network.vpn`) and the Cloud Interconnect
attachments (`gcp.network.interconnect`) of `gcp-network-hub`.

## Routes announced on-premises

The environment VPCs peer with the hub VPC. A Cloud Router in DEFAULT mode
announces only the subnets of its own VPC
([advertised routes](https://docs.cloud.google.com/network-connectivity/docs/router/concepts/advertised-routes)),
so on-premises would never learn an environment range. When
`advertised_ip_ranges` is empty (the default), the hub routers therefore use
CUSTOM mode and announce:

| Prefix | Why |
|--------|-----|
| Every hub subnet (`ALL_SUBNETS` group) | What DEFAULT mode announced; it includes the inbound DNS addresses |
| Every `gcp.environments.<env>.cidr_block` | The peered environments |
| `35.199.192.0/19`, only with `hybrid_dns.forward_zones` | The source range of Cloud DNS forwarded queries; on-premises must route replies back over the VPN or Interconnect ([forwarding zones](https://docs.cloud.google.com/dns/docs/zones/forwarding-zones)) |

With no environment CIDR and no forward zone the router stays in DEFAULT mode.
An explicit `advertised_ip_ranges` wins: the router announces exactly that list,
plus `advertised_groups` on the VPN (default none, so add `[ALL_SUBNETS]` to keep
the hub subnets). A router the Interconnect creates (`create_router`, default
`true`) keeps `ALL_SUBNETS` in CUSTOM mode; an existing router keeps its own
advertisement settings.

The environments learn the on-premises prefixes through the peering: the hub
side exports and the spoke side imports custom routes.

To check what a session announces:

```bash
gcloud compute routers get-status <router> --region=<region> --project=<hub-project> \
  --format='yaml(result.bestRoutesForRouter, result.bgpPeerStatus[].advertisedRoutes)'
```

## DNS

**On-premises to GCP.** With the VPN or an Interconnect on,
`gcp.network.hybrid_dns.enable_inbound_forwarding` (default `true`) adds the
inbound DNS server policy `<prefix>-hub-inbound` to the hub VPC. The hub VPC is
the network the VPN and Interconnect land in, and inbound entry points are not
reachable across VPC peering
([server policies](https://docs.cloud.google.com/dns/docs/server-policies-overview)).
The hub VPC sees the internal zone, so on-premises resolvers can forward the
internal domain (`gcp.network.internal_domain`, default `internal.local`) to the entry points. List their addresses (one per hub subnet;
use one in the region of the VPN or Interconnect):

```bash
gcloud compute addresses list --project=<hub-project> --filter='purpose="DNS_RESOLVER"'
```

A VPC network takes one DNS server policy. Set `enable_inbound_forwarding: false`
if another team manages the hub VPC's policy.

**GCP to on-premises.** `gcp.network.hybrid_dns.forward_zones` creates one
forwarding zone `fwd-<key>` per entry, bound to the hub VPC, that forwards its
domain to `target_ips` over the private path:

```yaml
gcp:
  network:
    hybrid_dns:
      forward_zones:
        corp:
          dns_name: corp.example.com.
          target_ips: [192.168.0.10, 192.168.0.11]
```

Allow TCP and UDP port 53 from `35.199.192.0/19` on the on-premises resolvers.
A forward zone may not be the internal domain or a subdomain of it (the plan
fails): two private zones bound to one network cannot share a DNS name, and a
forwarded subdomain would hide part of the internal zone. A parent domain is
fine, because Cloud DNS answers from the longest matching suffix
([overlapping zones](https://docs.cloud.google.com/dns/docs/zones/zones-overview)).
The zones are bound to the hub VPC only: an environment VPC that must resolve an
on-premises domain needs its own DNS peering zone for that domain that targets
the hub VPC.

## HA VPN pre-shared key rotation

### What a secret change does

`google_compute_vpn_tunnel` cannot update its secret in place. Each of these
**replaces the tunnels** (treat the arguments as ForceNew; confirm in a sandbox
plan before the first production rotation):

- moving from the legacy `shared_secret` to the write-only `vpn_shared_secret_wo`;
- raising `vpn_shared_secret_wo_version` to push a new `vpn_shared_secret_wo`.

Write-only values are not diffed, so changing `vpn_shared_secret_wo` without
raising the version does nothing; raising the version with the same value still
replaces the tunnels.

Replacement drops the tunnels, and the BGP sessions with them, until the
on-premises device is reconfigured with the new key. With
`gcp.network.ncc_hub.enabled` the tunnels are also linked to the NCC hybrid
spoke, and deleting a tunnel the spoke still links can be rejected by the API.

### Procedure (maintenance window)

1. Agree a window with the on-premises network team; HA only helps when the
   peer can take a new key on one tunnel at a time, which a replace does not
   offer.
2. Set the new key as the sensitive `vpn_shared_secret_wo` workspace variable and
   raise `vpn_shared_secret_wo_version` by one.
3. Plan. Expect `google_compute_vpn_tunnel` replacements (and the NCC hybrid
   spoke update, if enabled).
4. If the apply fails because the NCC spoke still links a tunnel, set
   `gcp.network.vpn.enabled: false`, apply (removes VPN and spoke), then set it
   back to `true` with the new key and apply again. This is a full outage for the
   window.
5. Configure the same key on the peer device, confirm the BGP sessions
   (`vpn_tunnel_statuses`) and that the NCC spoke is active.

### Migrating from the legacy input

Supply `vpn_shared_secret_wo` and leave `vpn_shared_secret` unset. This is a
tunnel replacement too, so do it in the same window.
