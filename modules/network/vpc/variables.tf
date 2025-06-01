/**
 * Copyright 2023 Ashes
 *
 * VPC Module - Variables
 */

variable "project_id" {
  description = "The ID of the project where this VPC will be created"
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC network"
  type        = string
  default     = "three-tier-vpc"
}

variable "region" {
  description = "The region where the subnets will be created"
  type        = string
  default     = "us-central1"
}

variable "auto_create_subnetworks" {
  description = "When set to true, the network is created in 'auto subnet mode' and it will create a subnet for each region automatically"
  type        = bool
  default     = false
}

variable "routing_mode" {
  description = "The network routing mode (default 'GLOBAL')"
  type        = string
  default     = "GLOBAL"
  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "Routing mode must be either 'REGIONAL' or 'GLOBAL'."
  }
}

variable "description" {
  description = "An optional description of this resource"
  type        = string
  default     = "Three-tier VPC network with public, private, and database subnets"
}

variable "delete_default_routes_on_create" {
  description = "If set to true, default routes (0.0.0.0/0) will be deleted immediately after network creation"
  type        = bool
  default     = false
}

variable "public_subnets_cidr" {
  description = "CIDR blocks for public subnets, one per zone"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets_cidr" {
  description = "CIDR blocks for private subnets, one per zone"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnets_cidr" {
  description = "CIDR blocks for database subnets, one per zone"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

variable "zones" {
  description = "List of zones in the region to spread the subnets across (should be 3 zones)"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]
  validation {
    condition     = length(var.zones) == 3
    error_message = "Exactly 3 zones must be specified for the three-tier architecture."
  }
} 