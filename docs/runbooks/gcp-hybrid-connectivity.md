# GCP hybrid connectivity: HA VPN pre-shared key rotation

Applies to the hub HA VPN (`gcp.network.vpn`, `gcp-network-hub`).

## What a secret change does

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

## Procedure (maintenance window)

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

## Migrating from the legacy input

Supply `vpn_shared_secret_wo` and leave `vpn_shared_secret` unset. This is a
tunnel replacement too, so do it in the same window.
