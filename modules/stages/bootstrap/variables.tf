variable "project_prefix" {
  description = "Prefix to use for project names"
  type        = string
}

variable "org_id" {
  description = "Organization ID"
  type        = string
}

variable "billing_account" {
  description = "Billing Account ID"
  type        = string
}

variable "admin_email" {
  description = "Email address for the organization administrator"
  type        = string
}

variable "github_org" {
  description = "GitHub Organization"
  type        = string
}

variable "github_repo" {
  description = "GitHub Repository"
  type        = string
}

# Terraform Cloud Configuration
variable "enable_tfc_oidc" {
  description = "Enable Terraform Cloud OIDC for Dynamic Credentials"
  type        = bool
  default     = true
}

variable "tfc_organization" {
  description = "Terraform Cloud organization name"
  type        = string
  default     = null
}

variable "tfc_workspaces" {
  description = "List of TFC workspaces to grant access to Terraform Admin SA"
  type        = list(string)
  default     = ["organization-prod"]
}
