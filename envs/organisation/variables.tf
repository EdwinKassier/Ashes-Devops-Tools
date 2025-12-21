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

variable "admin_email" {
  description = "Email address for the organization administrator"
  type        = string
}

variable "developers_group_email" {
  description = "Email address for the developers group"
  type        = string
}
