# Example: create a Cloud Armor policy with OWASP ModSecurity rules enabled,
# adaptive protection, a geo-block for high-risk regions, and a rate-limit
# rule for authenticated API endpoints.
#
# Two match types are supported in custom_rules.match_conditions — use exactly one:
#
#   1. versioned_expr + config  — IP-based matching (SRC_IPS_V1)
#   2. expr                     — CEL expression (headers, paths, geo, custom logic)
#
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
    # ── Example 1: IP-based block (versioned_expr path) ────────────────────────
    block_untrusted_ips = {
      action      = "deny(403)"
      priority    = 100
      description = "Block a known malicious IP range"
      match_conditions = {
        versioned_expr = "SRC_IPS_V1"
        config = {
          src_ip_ranges = ["192.0.2.0/24"]
        }
      }
    }

    # ── Example 2: Rate limiting by IP (versioned_expr + rate_limit_options) ───
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
        # enforce_on_key: set to a scalar value (IP, ALL, HTTP_HEADER, etc.) OR
        # omit it to use enforce_on_key_configs instead. Never set both.
        enforce_on_key = "IP"
      }
    }

    # ── Example 3: CEL expression match (header/path/geo rule) ─────────────────
    block_scraper_user_agents = {
      action      = "deny(403)"
      priority    = 300
      description = "Block requests from known scraper User-Agent strings"
      match_conditions = {
        # expr and versioned_expr are mutually exclusive — use one, not both.
        expr = "request.headers['user-agent'].lower().contains('scrapy') || request.headers['user-agent'].lower().contains('python-requests')"
      }
    }
  }
}
