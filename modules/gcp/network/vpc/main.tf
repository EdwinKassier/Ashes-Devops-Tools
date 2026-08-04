/**
 * Copyright 2023 Ashes
 *
 * VPC Module - Main Configuration
 *
 * This module creates a Google Cloud VPC network and optionally configures it as
 * a Shared VPC Host project. It is a foundational module that should be composed
 * with other modules (subnets, firewalls, etc.) to build a complete network.
 */

# Deletion protection guard — present only when enable_deletion_protection = true.
# Terraform's prevent_destroy must be a static literal; it cannot reference a variable.
# This guard resource carries prevent_destroy = true and is created conditionally so
# that removing it (by toggling the flag) is also blocked, forcing an explicit state rm.
resource "terraform_data" "deletion_protection_guard" {
  count = var.enable_deletion_protection ? 1 : 0

  input = var.vpc_name

  lifecycle {
    prevent_destroy = true
  }
}

# VPC resource
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = var.auto_create_subnetworks
  routing_mode            = var.routing_mode
  project                 = var.project_id
  description             = var.description

  delete_default_routes_on_create = var.delete_default_routes_on_create

}

# Shared VPC Host Project
resource "google_compute_shared_vpc_host_project" "host" {
  count      = var.enable_shared_vpc_host ? 1 : 0
  project    = var.project_id
  depends_on = [google_compute_network.vpc]
}