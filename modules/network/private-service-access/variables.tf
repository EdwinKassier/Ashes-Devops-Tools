/**
 * Copyright 2023 Ashes
 *
 * Private Service Access Module - Variables
 */

variable "project_id" {
  description = "The project ID where the address and peering will be created"
  type        = string
}

variable "vpc_network" {
  description = "The self-link of the VPC network to peer with Google Services"
  type        = string
}

variable "name" {
  description = "Name for the allocated IP range"
  type        = string
  default     = "google-managed-services-ip-range"
}

variable "description" {
  description = "Description for the allocated IP range"
  type        = string
  default     = "Allocated IP range for Google Private Service Access"
}

variable "address" {
  description = "The IP address (or starting address) to reserve (optional, auto-assigned if not specified)"
  type        = string
  default     = null
}

variable "prefix_length" {
  description = "The prefix length of the IP range (e.g., 16 for /16)"
  type        = number
  default     = 16
}

variable "ip_version" {
  description = "The IP version (IPV4 or IPV6)"
  type        = string
  default     = "IPV4"
}

variable "labels" {
  description = "Labels to apply to the allocated address"
  type        = map(string)
  default     = {}
}

variable "service" {
  description = "The service to peer with (default is servicenetworking.googleapis.com)"
  type        = string
  default     = "servicenetworking.googleapis.com"
}
