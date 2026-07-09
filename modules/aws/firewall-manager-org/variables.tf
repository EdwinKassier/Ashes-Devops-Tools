variable "enable_firewall_manager" {
  description = "Master toggle for AWS Firewall Manager. When false the module creates neither the admin-account registration nor any FMS policies."
  type        = bool
  default     = true
}

variable "fms_admin_account_id" {
  description = "12-digit account ID nominated as the Firewall Manager administrator (the Security Tooling account). Registered from the management account via the aliased provider. Required when enable_firewall_manager is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_firewall_manager || can(regex("^[0-9]{12}$", var.fms_admin_account_id))
    error_message = "fms_admin_account_id must be a 12-digit AWS account ID when enable_firewall_manager is true."
  }
}

variable "fms_policies" {
  description = "Firewall Manager policies to enforce org-wide, keyed by policy name. Each policy pins a resource_type, an FMS policy type (e.g. SECURITY_GROUPS_COMMON, WAFV2, DNS_FIREWALL, NETWORK_FIREWALL), an optional remediation flag, and the type-specific managed_service_data JSON blob."
  type = map(object({
    resource_type        = string
    type                 = string
    remediation_enabled  = optional(bool, true)
    managed_service_data = optional(string)
  }))

  default = {
    security-group-audit = {
      resource_type        = "AWS::EC2::SecurityGroup"
      type                 = "SECURITY_GROUPS_COMMON"
      managed_service_data = "{\"type\":\"SECURITY_GROUPS_COMMON\",\"securityGroups\":[{\"id\":\"sg-000000000000\"}],\"revertManualSecurityGroupChanges\":false,\"exclusiveResourceSecurityGroupManagement\":false,\"applyToAllEC2InstanceENIs\":false}"
    }
  }
}
