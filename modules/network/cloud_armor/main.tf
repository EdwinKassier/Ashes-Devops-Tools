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

# OWASP Core Rule Set Rules (when enabled)
locals {
  owasp_rules = var.enable_owasp_rules ? {
    "sqli" = {
      rule_id     = "sqli-v33-stable"
      priority    = 1000
      description = "SQL Injection protection"
    }
    "xss" = {
      rule_id     = "xss-v33-stable"
      priority    = 1001
      description = "Cross-site scripting protection"
    }
    "lfi" = {
      rule_id     = "lfi-v33-stable"
      priority    = 1002
      description = "Local file inclusion protection"
    }
    "rfi" = {
      rule_id     = "rfi-v33-stable"
      priority    = 1003
      description = "Remote file inclusion protection"
    }
    "rce" = {
      rule_id     = "rce-v33-stable"
      priority    = 1004
      description = "Remote code execution protection"
    }
    "scanner" = {
      rule_id     = "scannerdetection-v33-stable"
      priority    = 1005
      description = "Scanner detection"
    }
    "protocol" = {
      rule_id     = "protocolattack-v33-stable"
      priority    = 1006
      description = "Protocol attack protection"
    }
  } : {}
}

# OWASP Preconfigured WAF Rules
resource "google_compute_security_policy_rule" "owasp_rules" {
  for_each = local.owasp_rules

  project         = var.project_id
  security_policy = google_compute_security_policy.policy.name
  action          = "deny(403)"
  priority        = each.value.priority
  description     = each.value.description

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('${each.value.rule_id}', {'sensitivity': ${var.owasp_sensitivity}})"
    }
  }
}

# Additional Preconfigured WAF Rules
resource "google_compute_security_policy_rule" "preconfigured_waf_rules" {
  for_each = { for r in var.preconfigured_waf_rules : r.rule_id => r }

  project         = var.project_id
  security_policy = google_compute_security_policy.policy.name
  action          = each.value.action
  priority        = each.value.priority
  description     = each.value.description

  match {
    expr {
      expression = "evaluatePreconfiguredWaf('${each.value.rule_id}', {'sensitivity': ${each.value.sensitivity}})"
    }
  }
} 