variable "project_prefix" {
  description = "Prefix used for project naming"
  type        = string
}

variable "default_region" {
  description = "Default GCP region for resources"
  type        = string
}

variable "hub_project_id" {
  description = "Project ID for the network hub"
  type        = string
}

variable "dns_project_id" {
  description = "Project ID for the DNS hub"
  type        = string
}

variable "spoke_project_ids" {
  description = "Map of spoke project IDs to attach to Shared VPC"
  type        = map(string)
}

variable "org_id" {
  description = "Organization ID (format: organizations/123456789)"
  type        = string
}

variable "folders" {
  description = "Map of folder objects to attach policies to"
  type        = map(any)
}

variable "internal_domain" {
  description = "Internal domain for private DNS zone (e.g., 'mycompany.com')"
  type        = string
  default     = "internal.local"
}
