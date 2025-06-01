variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com')"
  type        = string
}

variable "project_prefix" {
  description = "Prefix to use for project names"
  type        = string
  default     = "my-org"
}

variable "organization_name" {
  description = "Name of the organization"
  type        = string
  default     = "My Organization"
}

variable "customer_id" {
  description = "The customer ID of the Google Cloud organization (e.g., 'A01b123xz')"
  type        = string
}

variable "billing_account" {
  description = "Billing account ID to associate with projects"
  type        = string
}

variable "default_region" {
  description = "Default region for resources"
  type        = string
  default     = "europe-west1"
}

# Output all variables for reference
output "domain" {
  value = var.domain
}

output "project_prefix" {
  value = var.project_prefix
}

output "organization_name" {
  value = var.organization_name
}

output "customer_id" {
  sensitive = true
  value     = var.customer_id
}

output "billing_account" {
  sensitive = true
  value     = var.billing_account
}

output "default_region" {
  value = var.default_region
}
