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
  description = "Name of the Private Service Connect endpoint (the global forwarding rule). Google's rule for an endpoint for Google APIs: 1-20 characters, lower-case letters and numbers only, starting with a letter."
  type        = string

  validation {
    # Source: https://docs.cloud.google.com/vpc/docs/configure-private-service-connect-apis (checked 2026-11-12).
    condition     = can(regex("^[a-z][a-z0-9]{0,19}$", var.name))
    error_message = "name must follow Google's rule for a Private Service Connect endpoint for Google APIs: \"The name must be a string of 1-20 characters, containing only lower-case letters and numbers. The name must start with a letter.\" Hyphens are not allowed."
  }
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
  description = "The internal IPv4 address of the endpoint (required: Google reserves an endpoint address only with an explicit IP or an internal range). It must be a single IPv4 address. Google also requires it to be outside every primary and secondary subnet range of the VPC network and of any network peered with it; this module does not check that (the net-hub and net-spoke compositions check it against their VPC's subnets)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.address)) && try(cidrhost("${var.address}/32", 0) == var.address, false)
    error_message = "address must be a single IPv4 address (for example 10.0.255.254), not a range or an IPv6 address."
  }
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
