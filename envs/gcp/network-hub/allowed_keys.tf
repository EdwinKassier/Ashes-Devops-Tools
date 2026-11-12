# Key allowlists of the untyped (type = any) inputs of this root or module. The
# variable validations reject any key outside these lists. Each list must equal
# the attributes of the typed object the value is forwarded to: an extra key
# would be dropped silently by type conversion, and a missing key could not be
# set. scripts/check-any-allowlists.py (make consistency) compares every list
# with the stage type named in scripts/any-allowlists.json.
locals {
  allowed_keys = {
    # modules/gcp/stages/network-hub vpn
    vpn = {
      self                 = ["enabled", "tunnel_count", "router_asn", "peer_asn", "peer_gateway_ips", "local_ips", "peer_ips", "site_to_site_data_transfer", "advertised_groups", "advertised_ip_ranges"]
      advertised_ip_ranges = ["range", "description"]
    }
    # modules/gcp/stages/network-hub interconnects
    interconnects = {
      self                 = ["region", "interconnect_type", "router_name", "router_asn", "create_router", "interconnect_self_link", "vlan_tag", "bandwidth", "edge_availability_domain", "mtu", "admin_enabled", "encryption", "create_bgp_peer", "interface_ip_range", "peer_ip_address", "peer_asn", "enable_bfd", "advertised_ip_ranges"]
      advertised_ip_ranges = ["range", "description"]
    }
    # modules/gcp/stages/network-hub hub_additional_regions
    hub_additional_regions = {
      self             = ["subnet_cidrs", "secondary_ranges", "nat"]
      subnet_cidrs     = ["public", "private", "database"]
      secondary_ranges = ["range_name", "ip_cidr_range"]
    }
  }
}
