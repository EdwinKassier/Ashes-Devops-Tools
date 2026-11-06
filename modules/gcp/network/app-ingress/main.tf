# Golden-path front door for a Cloud Run service: a global external
# HTTPS load balancer with a Google-managed certificate, HTTP->HTTPS redirect,
# optional Cloud Armor and optional DNS record. Compose this in front of a
# modules/gcp/compute/cloud-run service to expose it securely.

# Reserved anycast IP the DNS record points at.
resource "google_compute_global_address" "this" {
  project = var.project_id
  name    = "${var.name}-ip"
  labels  = var.labels
}

# Serverless NEG targeting the Cloud Run service.
resource "google_compute_region_network_endpoint_group" "this" {
  project               = var.project_id
  name                  = "${var.name}-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.cloud_run_service_name
  }
}

resource "google_compute_backend_service" "this" {
  project    = var.project_id
  name       = "${var.name}-backend"
  protocol   = "HTTPS"
  enable_cdn = var.enable_cdn

  # Access logging on for the front door.
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  security_policy = var.security_policy_id

  backend {
    group = google_compute_region_network_endpoint_group.this.id
  }
}

resource "google_compute_url_map" "this" {
  project         = var.project_id
  name            = "${var.name}-urlmap"
  default_service = google_compute_backend_service.this.id
}

resource "google_compute_managed_ssl_certificate" "this" {
  project = var.project_id
  name    = "${var.name}-cert"

  managed {
    domains = var.domains
  }
}

resource "google_compute_target_https_proxy" "this" {
  project          = var.project_id
  name             = "${var.name}-https-proxy"
  url_map          = google_compute_url_map.this.id
  ssl_certificates = [google_compute_managed_ssl_certificate.this.id]

  # Modern TLS only.
  ssl_policy = var.ssl_policy_id
}

resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = "${var.name}-https"
  target                = google_compute_target_https_proxy.this.id
  ip_address            = google_compute_global_address.this.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = var.labels
}

# HTTP listener that redirects to HTTPS (no plaintext serving).
resource "google_compute_url_map" "redirect" {
  project = var.project_id
  name    = "${var.name}-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "${var.name}-http-proxy"
  url_map = google_compute_url_map.redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project               = var.project_id
  name                  = "${var.name}-http"
  target                = google_compute_target_http_proxy.redirect.id
  ip_address            = google_compute_global_address.this.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = var.labels
}

# Optional DNS A record pointing the domain(s) at the load balancer.
resource "google_dns_record_set" "this" {
  for_each = var.dns_managed_zone == null ? toset([]) : toset(var.domains)

  project      = var.project_id
  managed_zone = var.dns_managed_zone
  name         = "${each.value}."
  type         = "A"
  ttl          = var.dns_ttl
  rrdatas      = [google_compute_global_address.this.address]
}
