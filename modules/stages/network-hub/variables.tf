variable "project_prefix" {
  description = "Prefix used for project naming"
  type        = string
}

variable "hub_vpc_cidr_block" {
  description = "CIDR block for the hub VPC (e.g. \"10.0.0.0/16\"). Required — set via IPAM or per-environment tfvars."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.hub_vpc_cidr_block))
    error_message = "hub_vpc_cidr_block must be a valid CIDR notation."
  }
}

variable "dns_hub_vpc_cidr_block" {
  description = "CIDR block for the DNS hub VPC (e.g. \"10.1.0.0/16\"). Required — must not overlap with hub_vpc_cidr_block."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.dns_hub_vpc_cidr_block))
    error_message = "dns_hub_vpc_cidr_block must be a valid CIDR notation."
  }
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
  type = map(object({
    id           = string
    name         = string
    display_name = string
  }))
}

variable "internal_domain" {
  description = "Internal domain for private DNS zone (e.g., 'mycompany.com')"
  type        = string
  default     = "internal.local"
}
