variable "enabled_features" {
  description = "IAM organization features to enable for centralized root access management. Valid values are RootCredentialsManagement (centrally manage member-account root credentials) and RootSessions (perform privileged root actions in member accounts from the management account)."
  type        = list(string)
  default     = ["RootCredentialsManagement", "RootSessions"]

  validation {
    condition     = alltrue([for f in var.enabled_features : contains(["RootCredentialsManagement", "RootSessions"], f)])
    error_message = "Each entry in enabled_features must be one of: RootCredentialsManagement, RootSessions."
  }
}
