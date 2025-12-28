/**
 * Copyright 2023 Ashes
 *
 * VPC Module - Main Configuration
 *
 * This module creates a Google Cloud VPC network and optionally configures it as
 * a Shared VPC Host project. It is a foundational module that should be composed
 * with other modules (subnets, firewalls, etc.) to build a complete network.
 */

# VPC resource
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = var.auto_create_subnetworks
  routing_mode            = var.routing_mode
  project                 = var.project_id
  description             = var.description

  delete_default_routes_on_create = var.delete_default_routes_on_create

  # Prevent accidental deletion of the network
  lifecycle {
    prevent_destroy = false # Set to true for production usage
  }
}

# Shared VPC Host Project
resource "google_compute_shared_vpc_host_project" "host" {
  count      = var.enable_shared_vpc_host ? 1 : 0
  project    = var.project_id
  depends_on = [google_compute_network.vpc]
}