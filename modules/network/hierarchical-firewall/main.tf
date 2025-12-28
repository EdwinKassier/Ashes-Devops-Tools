/**
 * Copyright 2023 Ashes
 *
 * Hierarchical Firewall Policy Module - Main Configuration
 * 
 * Creates organizational or folder-level firewall policies that apply
 * across multiple projects in a hierarchical manner.
 */

# -----------------------------------------------------------------------------
# FIREWALL POLICY (Org or Folder level)
# -----------------------------------------------------------------------------

resource "google_compute_firewall_policy" "policy" {
  short_name  = var.policy_name
  parent      = var.parent
  description = var.description
}

# -----------------------------------------------------------------------------
# FIREWALL POLICY RULES
# -----------------------------------------------------------------------------

resource "google_compute_firewall_policy_rule" "rules" {
  for_each = { for idx, rule in var.rules : rule.priority => rule }

  firewall_policy = google_compute_firewall_policy.policy.id
  priority        = each.value.priority
  action          = each.value.action
  direction       = each.value.direction
  description     = try(each.value.description, null)
  disabled        = try(each.value.disabled, false)
  enable_logging  = try(each.value.enable_logging, var.enable_logging)

  # Match configuration
  match {
    # Layer 4 config
    dynamic "layer4_configs" {
      for_each = each.value.layer4_configs
      content {
        ip_protocol = layer4_configs.value.ip_protocol
        ports       = try(layer4_configs.value.ports, null)
      }
    }

    # Source configuration (for INGRESS)
    src_ip_ranges            = each.value.direction == "INGRESS" ? try(each.value.src_ip_ranges, null) : null
    src_fqdns                = each.value.direction == "INGRESS" ? try(each.value.src_fqdns, null) : null
    src_region_codes         = each.value.direction == "INGRESS" ? try(each.value.src_region_codes, null) : null
    src_threat_intelligences = each.value.direction == "INGRESS" ? try(each.value.src_threat_intelligences, null) : null

    # Destination configuration (for EGRESS)
    dest_ip_ranges            = each.value.direction == "EGRESS" ? try(each.value.dest_ip_ranges, null) : null
    dest_fqdns                = each.value.direction == "EGRESS" ? try(each.value.dest_fqdns, null) : null
    dest_region_codes         = each.value.direction == "EGRESS" ? try(each.value.dest_region_codes, null) : null
    dest_threat_intelligences = each.value.direction == "EGRESS" ? try(each.value.dest_threat_intelligences, null) : null
  }

  # Target resources (networks to apply to)
  target_resources = try(each.value.target_networks, null)

  # Target service accounts
  target_service_accounts = try(each.value.target_service_accounts, null)
}

# -----------------------------------------------------------------------------
# FIREWALL POLICY ASSOCIATION (attach to folders/org)
# -----------------------------------------------------------------------------

resource "google_compute_firewall_policy_association" "associations" {
  for_each = toset(var.associations)

  name              = "${var.policy_name}-${replace(each.value, "/", "-")}"
  attachment_target = each.value
  firewall_policy   = google_compute_firewall_policy.policy.id
}
