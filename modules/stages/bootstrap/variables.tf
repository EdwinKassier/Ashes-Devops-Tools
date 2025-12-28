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
