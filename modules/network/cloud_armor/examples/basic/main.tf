# Example: create a Cloud Armor policy with OWASP ModSecurity rules enabled,
# adaptive protection, a geo-block for high-risk regions, and a rate-limit
# rule for authenticated API endpoints.
# In a real deployment replace the locals below with data sources or remote state.

locals {
  project_id = "my-project-id"
}

module "cloud_armor" {
  source = "../../"

  project_id  = local.project_id
  policy_name = "api-gateway-policy"
  description = "Edge protection for the public API gateway"

  default_rule_action = "allow"

  enable_owasp_rules         = true
  owasp_sensitivity          = 2
  enable_adaptive_protection = true
  enable_log4j_protection    = true

  custom_rules = {
    block_high_risk_regions = {
      action      = "deny(403)"
      priority    = 100
      description = "Block traffic from regions with high abuse rates"
      match_conditions = {
        versioned_expr = "SRC_IPS_V1"
        config = {
          src_ip_ranges = ["0.0.0.0/0"]
        }
      }
    }

    rate_limit_api = {
      action      = "rate_based_ban"
      priority    = 200
      description = "Limit each IP to 100 API requests per minute"
      match_conditions = {
        versioned_expr = "SRC_IPS_V1"
        config = {
          src_ip_ranges = ["0.0.0.0/0"]
        }
      }
      rate_limit_options = {
        threshold_count     = 100
        interval_sec        = 60
        conform_action      = "allow"
        exceed_action       = "deny(429)"
        enforce_on_key      = "IP"
        enforce_on_key_type = "IP"
      }
    }
  }
}

output "security_policy_id" {
  description = "Resource ID of the Cloud Armor security policy"
  value       = module.cloud_armor.id
}

output "security_policy_self_link" {
  description = "Self-link — attach this to a backend service's security_policy field"
  value       = module.cloud_armor.self_link
}
