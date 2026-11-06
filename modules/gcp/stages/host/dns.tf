# Host stage: Cloud DNS managed zones.
# Part of modules/gcp/stages/host.

# =============================================================================
# DNS MANAGEMENT
# =============================================================================

module "dns" {
  source   = "../../network/dns"
  for_each = var.dns_zones

  project_id = var.project_id
  zone_name  = each.key
  dns_name   = each.value.dns_name
  # try() only catches a MISSING attribute; optional() attributes arrive as null,
  # so null-coalesce explicitly (a null peering_network failed the dns module).
  description     = try(coalesce(each.value.description, "Managed DNS zone for ${each.key}"), "Managed DNS zone for ${each.key}")
  visibility      = each.value.visibility
  dnssec_enabled  = try(coalesce(each.value.dnssec_enabled, false), false)
  peering_network = try(each.value.peering_network, null) == null ? "" : each.value.peering_network
  enable_logging  = true
  labels          = var.labels

  private_visibility_networks = each.value.visibility == "private" ? [
    var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link
  ] : []

  records = try(each.value.records, null) == null ? [] : each.value.records
}
