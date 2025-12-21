resource "google_compute_security_policy" "policy" {
  provider    = google
  project     = var.project_id
  name        = var.policy_name
  description = var.description

  # Default rule (executed last)
  rule {
    action   = var.default_rule_action
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default rule, higher priority overrides it"
  }

  # Dynamic block for custom rules
  dynamic "rule" {
    for_each = var.custom_rules
    content {
      action      = rule.value.action
      priority    = rule.value.priority
      description = rule.value.description

      match {
        versioned_expr = rule.value.match_conditions.versioned_expr
        config {
          src_ip_ranges = try(rule.value.match_conditions.config.src_ip_ranges, null)
        }
      }

      dynamic "rate_limit_options" {
        for_each = try(rule.value.rate_limit_options, null) != null ? [rule.value.rate_limit_options] : []
        content {
          rate_limit_threshold {
            count        = rate_limit_options.value.threshold_count
            interval_sec = rate_limit_options.value.interval_sec
          }
          conform_action = try(rate_limit_options.value.conform_action, "allow")
          exceed_action  = try(rate_limit_options.value.exceed_action, "deny(429)")
          enforce_on_key = try(rate_limit_options.value.enforce_on_key, null)
          enforce_on_key_configs {
            enforce_on_key_type = try(rate_limit_options.value.enforce_on_key_type, "ALL")
          }
        }
      }
    }
  }

  # Optional: Advanced options block
  dynamic "adaptive_protection_config" {
    for_each = var.enable_adaptive_protection ? [1] : []
    content {
      layer_7_ddos_defense_config {
        enable = true
      }
    }
  }
} 