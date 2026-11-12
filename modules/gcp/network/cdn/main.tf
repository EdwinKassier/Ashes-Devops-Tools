/**
 * Copyright 2023 Ashes
 *
 * CDN Module - Main Configuration
 */

locals {
  create_ssl = length(var.domains) > 0
}

# 1. Global IP Address
resource "google_compute_global_address" "default" {
  provider = google
  project  = var.project_id
  name     = "${var.lb_name}-ip"
  labels   = var.labels
}

# 2. Managed SSL Certificate (Optional)
resource "google_compute_managed_ssl_certificate" "default" {
  count    = local.create_ssl ? 1 : 0
  provider = google
  project  = var.project_id
  name     = "${var.lb_name}-cert"

  managed {
    domains = var.domains
  }
}

# 3. Backend Service (Global, CDN Enabled)
resource "google_compute_backend_service" "default" {
  provider = google
  project  = var.project_id
  name     = "${var.lb_name}-backend"
  protocol = "HTTP"

  load_balancing_scheme = "EXTERNAL"
  enable_cdn            = var.enable_cdn
  security_policy       = var.security_policy

  dynamic "backend" {
    for_each = var.backend_groups
    content {
      group           = backend.value.group
      balancing_mode  = backend.value.balancing_mode
      capacity_scaler = backend.value.capacity_scaler
      description     = backend.value.description
    }
  }

  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [var.cdn_policy] : []
    content {
      cache_mode                   = cdn_policy.value.cache_mode
      client_ttl                   = cdn_policy.value.client_ttl
      default_ttl                  = cdn_policy.value.default_ttl
      max_ttl                      = cdn_policy.value.max_ttl
      negative_caching             = cdn_policy.value.negative_caching
      signed_url_cache_max_age_sec = cdn_policy.value.signed_url_cache_max_age_sec
    }
  }
}

# 4. URL Map
resource "google_compute_url_map" "default" {
  provider        = google
  project         = var.project_id
  name            = "${var.lb_name}-url-map"
  default_service = google_compute_backend_service.default.id
}

# 5. SSL policy: the TLS floor of the HTTPS proxy when the caller passes none.
# Without one, the proxy uses Google's default COMPATIBLE profile, which accepts
# TLS 1.0 and 1.1 and older cipher suites.
resource "google_compute_ssl_policy" "this" {
  count = var.ssl_policy_id == null ? 1 : 0

  provider        = google
  project         = var.project_id
  name            = "${var.lb_name}-tls"
  description     = "TLS ${replace(trimprefix(var.min_tls_version, "TLS_"), "_", ".")} minimum for ${var.lb_name} (cdn)."
  profile         = var.ssl_policy_profile
  min_tls_version = var.min_tls_version
}

# 6. Target HTTPS Proxy
resource "google_compute_target_https_proxy" "default" {
  provider         = google
  project          = var.project_id
  name             = "${var.lb_name}-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = local.create_ssl ? [google_compute_managed_ssl_certificate.default[0].id] : []

  # A caller-supplied policy wins; else the TLS-floor policy above.
  ssl_policy = var.ssl_policy_id != null ? var.ssl_policy_id : google_compute_ssl_policy.this[0].id
}

# 7. Global Forwarding Rule
resource "google_compute_global_forwarding_rule" "default" {
  provider              = google
  project               = var.project_id
  name                  = "${var.lb_name}-forwarding-rule"
  target                = google_compute_target_https_proxy.default.id
  ip_address            = google_compute_global_address.default.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
  labels                = var.labels
}

# =============================================================================
# HTTP TO HTTPS REDIRECT (Optional but recommended)
# =============================================================================

# 8. URL Map for HTTP redirect
resource "google_compute_url_map" "redirect" {
  count    = var.enable_http_redirect ? 1 : 0
  provider = google
  project  = var.project_id
  name     = "${var.lb_name}-http-redirect-url-map"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# 9. HTTP Target Proxy for redirect
resource "google_compute_target_http_proxy" "redirect" {
  count    = var.enable_http_redirect ? 1 : 0
  provider = google
  project  = var.project_id
  name     = "${var.lb_name}-http-redirect-proxy"
  url_map  = google_compute_url_map.redirect[0].id
}

# 10. HTTP Forwarding Rule for redirect
resource "google_compute_global_forwarding_rule" "http_redirect" {
  count                 = var.enable_http_redirect ? 1 : 0
  provider              = google
  project               = var.project_id
  name                  = "${var.lb_name}-http-redirect"
  target                = google_compute_target_http_proxy.redirect[0].id
  ip_address            = google_compute_global_address.default.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
  labels                = var.labels
}
