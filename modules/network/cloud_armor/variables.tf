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
  type        = map(any)
  default     = {}
}

variable "enable_adaptive_protection" {
  description = "Enable adaptive protection features"
  type        = bool
  default     = false
} 