variable "domain" { type = string }
variable "org_id" { type = string }
variable "admin_project_id" { type = string }
variable "admin_project_number" { type = string }
variable "customer_id" { type = string }
variable "admin_email" { type = string }
variable "break_glass_user" {
  type    = string
  default = null
}
variable "terraform_admin_email" { type = string }
variable "billing_account" { type = string }
variable "project_prefix" { type = string }

variable "environments" {
  description = "Map of environment definitions"
  type = map(object({
    display_name = string
    description  = string
    groups = map(object({
      role = string
    }))
    projects = map(object({
      name            = string
      billing_account = optional(string)
      labels          = map(string)
    }))
  }))
}

variable "developers_group_email" { type = string }
variable "organization_admin_groups" { type = list(string) }
variable "billing_admin_groups" { type = list(string) }
variable "default_region" { type = string }
variable "allowed_regions" { type = list(string) }
variable "security_contact_email" { type = string }
variable "billing_contact_email" { type = string }
variable "monthly_budget_amount" { type = number }
variable "budget_currency" { type = string }
