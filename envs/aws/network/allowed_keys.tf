# Key allowlists of the untyped (type = any) inputs of this root or module. The
# variable validations reject any key outside these lists. Each list must equal
# the attributes of the typed object the value is forwarded to: an extra key
# would be dropped silently by type conversion, and a missing key could not be
# set. scripts/check-any-allowlists.py (make consistency) compares every list
# with the stage type named in scripts/any-allowlists.json.
locals {
  allowed_keys = {
    # modules/aws/stages/network-hub vpn
    vpn = {
      self = ["customer_gateway_ip", "customer_gateway_bgp_asn", "static_routes_only", "onprem_cidrs", "tunnel_inside_cidrs", "enable_acceleration", "preshared_key_storage"]
    }
  }
}
