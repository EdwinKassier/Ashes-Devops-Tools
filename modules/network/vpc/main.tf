/**
 * Copyright 2023 Ashes
 *
 * VPC Module - Main Configuration
 */


# VPC resource
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = var.auto_create_subnetworks
  routing_mode            = var.routing_mode
  project                 = var.project_id
  description             = var.description

  delete_default_routes_on_create = var.delete_default_routes_on_create
}

# Public subnets
resource "google_compute_subnetwork" "public" {
  count         = 3
  name          = "${var.vpc_name}-public-${var.zones[count.index]}"
  ip_cidr_range = var.public_subnets_cidr[count.index]
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  private_ip_google_access = true

  # Enable flow logs for security
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private subnets
resource "google_compute_subnetwork" "private" {
  count         = 3
  name          = "${var.vpc_name}-private-${var.zones[count.index]}"
  ip_cidr_range = var.private_subnets_cidr[count.index]
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  private_ip_google_access = true

  # Enable flow logs for security
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Database subnets
resource "google_compute_subnetwork" "database" {
  count         = 3
  name          = "${var.vpc_name}-db-${var.zones[count.index]}"
  ip_cidr_range = var.database_subnets_cidr[count.index]
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  private_ip_google_access = true

  # Enable flow logs for security
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router for NAT gateway
resource "google_compute_router" "router" {
  name    = "${var.vpc_name}-router"
  network = google_compute_network.vpc.id
  region  = var.region
  project = var.project_id
}

# NAT gateway for private subnets
resource "google_compute_router_nat" "nat" {
  name                               = "${var.vpc_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private[0].self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.private[1].self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.private[2].self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.database[0].self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.database[1].self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.database[2].self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
} 