# Example: Cloud Armor policy with OWASP managed rules and a custom rule
# that blocks traffic from a specific CIDR range.
# Attach policy_id to a Backend Service or external load balancer backend.

module "cloud_armor" {
  source = "../../modules/network/cloud_armor"

  project_id  = "my-project-id"
  policy_name = "api-gateway-policy"
  description = "WAF policy for public API gateway"

  default_rule_action = "allow"

  enable_owasp_rules         = true
  enable_adaptive_protection = true
  enable_log4j_protection    = true
  owasp_sensitivity          = 2

  custom_rules = {
    "block-legacy-infra" = {
      action      = "deny(403)"
      priority    = 1000
      description = "Block requests from decommissioned legacy CIDR"
      match_conditions = {
        versioned_expr = "SRC_IPS_V1"
        config = {
          src_ip_ranges = ["192.0.2.0/24"]
        }
      }
    }
  }
}

