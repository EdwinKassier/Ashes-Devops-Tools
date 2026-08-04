/**
 * Copyright 2023 Ashes
 *
 * Private Service Connect Module - Variables
 */

variable "project_id" {
  description = "The project ID where the PSC endpoint will be created"
  type        = string
}

variable "name" {
  description = "Name of the Private Service Connect endpoint"
  type        = string
}

variable "network" {
  description = "The self-link of the VPC network for the PSC endpoint"
  type        = string
}

variable "target" {
  description = "The target service to connect to. Must be 'all-apis' or 'vpc-sc'."
  type        = string
  default     = "all-apis"

  validation {
    condition     = contains(["all-apis", "vpc-sc"], var.target)
    error_message = "target must be 'all-apis' or 'vpc-sc'. This module implements global PSC for Google APIs only."
  }
}

variable "address_name" {
  description = "Name of the internal IP address to reserve"
  type        = string
  default     = null
}

variable "address" {
  description = "Specific IP address to reserve (optional, auto-assigned if not specified)"
  type        = string
  default     = null
}

variable "description" {
  description = "Description of the PSC endpoint"
  type        = string
  default     = "Private Service Connect endpoint managed by Terraform"
}

variable "labels" {
  description = "Labels to apply to the PSC resources"
  type        = map(string)
  default     = {}
}

variable "create_dns_zone" {
  description = "Create a private DNS zone for the PSC endpoint"
  type        = bool
  default     = true
}

variable "dns_zone_name" {
  description = "Name of the private DNS zone for PSC"
  type        = string
  default     = "psc-googleapis"
}
