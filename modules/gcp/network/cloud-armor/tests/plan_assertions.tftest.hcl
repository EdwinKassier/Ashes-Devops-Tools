# Plan assertions for the cloud-armor module: verify the default catch-all rule,
# the Log4Shell canary rule (on by default), OWASP rule fan-out and derived WAF
# expressions, custom rule rendering and adaptive protection toggles.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id  = "mock-project"
  policy_name = "mock-armor-policy"
}

run "defaults" {
  command = plan

  assert {
    condition     = google_compute_security_policy.policy.name == "mock-armor-policy" && google_compute_security_policy.policy.project == "mock-project"
    error_message = "Security policy must use the caller-supplied name and project."
  }

  assert {
    condition     = length(google_compute_security_policy.policy.rule) == 1
    error_message = "With no custom rules, only the default catch-all rule must be rendered inline."
  }

  assert {
    condition = alltrue([
      for r in google_compute_security_policy.policy.rule :
      r.action == "allow" && r.priority == 2147483647 && r.match[0].versioned_expr == "SRC_IPS_V1" && length(r.match[0].config[0].src_ip_ranges) == 1 && contains(r.match[0].config[0].src_ip_ranges, "*")
    ])
    error_message = "Default rule must be the lowest-priority (2147483647) SRC_IPS_V1 '*' match with action 'allow'."
  }

  assert {
    condition     = length(google_compute_security_policy_rule.log4j_protection) == 1
    error_message = "Log4Shell protection must be enabled by default."
  }

  assert {
    condition     = google_compute_security_policy_rule.log4j_protection[0].action == "deny(403)" && google_compute_security_policy_rule.log4j_protection[0].priority == 999
    error_message = "Log4Shell rule must deny(403) at priority 999 (ahead of the OWASP block)."
  }

  assert {
    condition     = strcontains(google_compute_security_policy_rule.log4j_protection[0].match[0].expr[0].expression, "log4j-v33-stable")
    error_message = "Log4Shell rule must evaluate the log4j-v33-stable preconfigured WAF signature."
  }

  assert {
    condition     = length(google_compute_security_policy_rule.owasp_rules) == 0
    error_message = "OWASP rules must be off by default."
  }

  assert {
    condition     = length(google_compute_security_policy.policy.adaptive_protection_config) == 0
    error_message = "Adaptive protection must be off by default."
  }
}

run "owasp_and_adaptive_enabled" {
  command = plan

  variables {
    enable_owasp_rules         = true
    owasp_sensitivity          = 1
    enable_adaptive_protection = true
    enable_log4j_protection    = false
    default_rule_action        = "deny"
  }

  assert {
    condition     = toset(keys(google_compute_security_policy_rule.owasp_rules)) == toset(["sqli", "xss", "lfi", "rfi", "rce", "scanner", "protocol"])
    error_message = "OWASP toggle must create the seven CRS rules keyed sqli/xss/lfi/rfi/rce/scanner/protocol."
  }

  assert {
    condition     = alltrue([for r in google_compute_security_policy_rule.owasp_rules : r.action == "deny(403)" && r.priority >= 1000 && r.priority <= 1006])
    error_message = "OWASP rules must deny(403) within the 1000-1006 priority band."
  }

  assert {
    condition     = google_compute_security_policy_rule.owasp_rules["sqli"].match[0].expr[0].expression == "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
    error_message = "OWASP expressions must be derived from the rule id and owasp_sensitivity."
  }

  assert {
    condition     = google_compute_security_policy_rule.owasp_rules["scanner"].match[0].expr[0].expression == "evaluatePreconfiguredWaf('scannerdetection-v33-stable', {'sensitivity': 1})"
    error_message = "The 'scanner' key must map to scannerdetection-v33-stable."
  }

  assert {
    condition     = length(google_compute_security_policy_rule.log4j_protection) == 0
    error_message = "enable_log4j_protection = false must drop the Log4Shell rule."
  }

  assert {
    condition     = google_compute_security_policy.policy.adaptive_protection_config[0].layer_7_ddos_defense_config[0].enable == true
    error_message = "Adaptive protection toggle must enable L7 DDoS defense."
  }

  assert {
    condition     = alltrue([for r in google_compute_security_policy.policy.rule : r.action == "deny" if r.priority == 2147483647])
    error_message = "default_rule_action = deny must flip the catch-all rule to deny."
  }
}

run "custom_and_preconfigured_rules" {
  command = plan

  variables {
    custom_rules = {
      allow_office = {
        action      = "allow"
        priority    = 100
        description = "office"
        match_conditions = {
          versioned_expr = "SRC_IPS_V1"
          config         = { src_ip_ranges = ["203.0.113.0/24"] }
        }
      }
      block_bots = {
        action   = "deny(403)"
        priority = 200
        match_conditions = {
          expr = "request.headers['user-agent'].contains('badbot')"
        }
      }
    }
    preconfigured_waf_rules = [
      { rule_id = "methodenforcement-v33-stable", action = "deny(403)", priority = 1100 },
    ]
  }

  # Inline custom rules live in a set whose computed `preview` attribute is
  # unknown at plan time, so with >1 rule the set cannot be inspected under
  # command = plan; their validation is covered in variables_validation.

  assert {
    condition     = length(google_compute_security_policy_rule.log4j_protection) == 1
    error_message = "Log4Shell rule must remain alongside custom rules."
  }

  assert {
    condition     = keys(google_compute_security_policy_rule.preconfigured_waf_rules) == ["methodenforcement-v33-stable"]
    error_message = "preconfigured_waf_rules must be keyed by rule_id."
  }

  assert {
    condition     = google_compute_security_policy_rule.preconfigured_waf_rules["methodenforcement-v33-stable"].match[0].expr[0].expression == "evaluatePreconfiguredWaf('methodenforcement-v33-stable', {'sensitivity': 2})"
    error_message = "Preconfigured WAF expression must default sensitivity to 2."
  }
}
