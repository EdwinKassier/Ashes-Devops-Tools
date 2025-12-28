variable "project_id" {
  description = "The project ID where the security policy will be created"
  type        = string
}

variable "policy_name" {
  description = "Name of the Cloud Armor security policy"
  type        = string
}

variable "description" {
  description = "Description of the Cloud Armor security policy"
  type        = string
  default     = "Cloud Armor security policy managed by Terraform"
}

variable "default_rule_action" {
  description = "Default rule action (allow/deny)"
  type        = string
  default     = "allow"

  validation {
    condition     = contains(["allow", "deny"], var.default_rule_action)
    error_message = "Default rule action must be either 'allow' or 'deny'."
  }
}

variable "custom_rules" {
  description = "Map of custom rules to apply to the security policy"
  type = map(object({
    action      = string
    priority    = number
    description = optional(string)
    match_conditions = object({
      versioned_expr = string
      config = object({
        src_ip_ranges = list(string)
      })
    })
    rate_limit_options = optional(object({
      threshold_count     = number
      interval_sec        = number
      conform_action      = optional(string)
      exceed_action       = optional(string)
      enforce_on_key      = optional(string)
      enforce_on_key_type = optional(string)
    }))
  }))
  default = {}
}

variable "enable_adaptive_protection" {
  description = "Enable adaptive protection features"
  type        = bool
  default     = false
}

variable "enable_owasp_rules" {
  description = "Enable preconfigured OWASP ModSecurity Core Rule Set"
  type        = bool
  default     = false
}

variable "owasp_sensitivity" {
  description = "OWASP rule sensitivity level (1-4, lower is more sensitive)"
  type        = number
  default     = 2

  validation {
    condition     = var.owasp_sensitivity >= 1 && var.owasp_sensitivity <= 4
    error_message = "OWASP sensitivity must be between 1 and 4."
  }
}

variable "preconfigured_waf_rules" {
  description = "Additional preconfigured WAF rules to enable"
  type = list(object({
    rule_id     = string
    action      = string
    priority    = number
    description = optional(string)
    sensitivity = optional(number, 2)
  }))
  default = []
  # Available rule IDs:
  # - sqli-v33-stable (SQL injection)
  # - xss-v33-stable (Cross-site scripting)
  # - lfi-v33-stable (Local file inclusion)
  # - rfi-v33-stable (Remote file inclusion)
  # - rce-v33-stable (Remote code execution)
  # - methodenforcement-v33-stable
  # - scannerdetection-v33-stable
  # - protocolattack-v33-stable
  # - php-v33-stable
  # - sessionfixation-v33-stable
} 