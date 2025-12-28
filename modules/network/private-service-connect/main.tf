/**
 * Copyright 2023 Ashes
 *
 * Private Service Connect Module - Main Configuration
 * 
 * Creates a Private Service Connect endpoint for accessing Google APIs
 * without using public IP addresses.
 */

locals {
  address_name = coalesce(var.address_name, "${var.name}-ip")

  # Map of Google API targets to their service attachment URIs
  google_targets = {
    "all-apis" = "all-apis"
    "vpc-sc"   = "vpc-sc"
  }

  is_google_api = contains(keys(local.google_targets), var.target)
}

# Reserve a global internal IP address for the PSC endpoint
resource "google_compute_global_address" "psc_address" {
  count = local.is_google_api ? 1 : 0

  project      = var.project_id
  name         = local.address_name
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = var.network
  address      = var.address
  labels       = var.labels
}

# Global forwarding rule for Google APIs
resource "google_compute_global_forwarding_rule" "psc_forwarding_rule" {
  count = local.is_google_api ? 1 : 0

  project               = var.project_id
  name                  = var.name
  target                = local.google_targets[var.target]
  network               = var.network
  ip_address            = google_compute_global_address.psc_address[0].id
  load_balancing_scheme = ""

  labels = var.labels
}

# Private DNS zone to route Google API traffic through PSC
resource "google_dns_managed_zone" "psc_dns" {
  count = local.is_google_api && var.create_dns_zone ? 1 : 0

  project     = var.project_id
  name        = var.dns_zone_name
  dns_name    = "googleapis.com."
  description = "Private DNS zone for Private Service Connect to Google APIs"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = var.network
    }
  }
}

# DNS record to route *.googleapis.com to the PSC endpoint
resource "google_dns_record_set" "psc_googleapis" {
  count = local.is_google_api && var.create_dns_zone ? 1 : 0

  project      = var.project_id
  managed_zone = google_dns_managed_zone.psc_dns[0].name
  name         = "*.googleapis.com."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.psc_address[0].address]
}

# DNS record for the base googleapis.com domain
resource "google_dns_record_set" "psc_googleapis_base" {
  count = local.is_google_api && var.create_dns_zone ? 1 : 0

  project      = var.project_id
  managed_zone = google_dns_managed_zone.psc_dns[0].name
  name         = "googleapis.com."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.psc_address[0].address]
}
