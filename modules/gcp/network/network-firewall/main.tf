resource "google_compute_firewall" "firewall_rule" {
  provider = google
  project  = var.project_id
  name     = var.firewall_rule_name
  network  = var.network

  direction = var.direction

  description = var.description

  priority = var.priority

  dynamic "allow" {
    for_each = var.allow_rules
    content {
      protocol = allow.value.protocol
      ports    = try(allow.value.ports, null)
    }
  }

  dynamic "deny" {
    for_each = var.deny_rules
    content {
      protocol = deny.value.protocol
      ports    = try(deny.value.ports, null)
    }
  }

  source_ranges = var.source_ranges
  target_tags   = var.target_tags
  source_tags   = var.source_tags

  disabled = var.disabled

  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      metadata = var.log_metadata
    }
  }
} 