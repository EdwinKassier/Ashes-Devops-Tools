/**
 * Copyright 2023 Ashes
 *
 * Internal HTTP(S) Load Balancer Module - Main Configuration
 *
 * Creates an internal HTTP(S) load balancer for L7 load balancing
 * of internal services within a VPC.
 */

# -----------------------------------------------------------------------------
# INTERNAL IP ADDRESS
# -----------------------------------------------------------------------------

resource "google_compute_address" "internal_ip" {
  count = var.create_static_ip ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-ip"
  region       = var.region
  subnetwork   = var.subnet
  address_type = "INTERNAL"
  purpose      = var.is_l7 ? "SHARED_LOADBALANCER_VIP" : "GCE_ENDPOINT"
  address      = var.ip_address
}

locals {
  ip_address = var.create_static_ip ? google_compute_address.internal_ip[0].address : var.ip_address
}

# -----------------------------------------------------------------------------
# HEALTH CHECK
# -----------------------------------------------------------------------------

resource "google_compute_health_check" "health_check" {
  count = var.create_health_check ? 1 : 0

  project = var.project_id
  name    = "${var.name}-health-check"

  check_interval_sec  = var.health_check_interval_sec
  timeout_sec         = var.health_check_timeout_sec
  healthy_threshold   = var.health_check_healthy_threshold
  unhealthy_threshold = var.health_check_unhealthy_threshold

  dynamic "http_health_check" {
    for_each = var.health_check_type == "HTTP" ? [1] : []
    content {
      port         = var.health_check_port
      request_path = var.health_check_request_path
    }
  }

  dynamic "https_health_check" {
    for_each = var.health_check_type == "HTTPS" ? [1] : []
    content {
      port         = var.health_check_port
      request_path = var.health_check_request_path
    }
  }

  dynamic "tcp_health_check" {
    for_each = var.health_check_type == "TCP" ? [1] : []
    content {
      port = var.health_check_port
    }
  }

  dynamic "grpc_health_check" {
    for_each = var.health_check_type == "GRPC" ? [1] : []
    content {
      port              = var.health_check_port
      grpc_service_name = var.grpc_service_name
    }
  }
}

locals {
  health_check = var.create_health_check ? google_compute_health_check.health_check[0].self_link : var.health_check_self_link
}

# -----------------------------------------------------------------------------
# BACKEND SERVICE (Regional)
# -----------------------------------------------------------------------------

resource "google_compute_region_backend_service" "backend" {
  project = var.project_id
  name    = "${var.name}-backend"
  region  = var.region

  protocol              = var.is_l7 ? "HTTP" : "TCP"
  load_balancing_scheme = var.is_l7 ? "INTERNAL_MANAGED" : "INTERNAL"
  timeout_sec           = var.backend_timeout_sec
  health_checks         = [local.health_check]

  session_affinity = var.session_affinity
  # locality_lb_policy is only valid for INTERNAL_MANAGED; INTERNAL
  # passthrough backend services reject it.
  locality_lb_policy              = var.is_l7 ? var.locality_lb_policy : null
  connection_draining_timeout_sec = var.connection_draining_timeout_sec

  dynamic "backend" {
    for_each = var.backends
    content {
      group           = backend.value.group
      balancing_mode  = try(backend.value.balancing_mode, "UTILIZATION")
      capacity_scaler = try(backend.value.capacity_scaler, 1.0)
      max_utilization = try(backend.value.max_utilization, 0.8)
      max_connections = try(backend.value.max_connections, null)
      max_rate        = try(backend.value.max_rate, null)
    }
  }

  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable      = true
      sample_rate = var.log_sample_rate
    }
  }
}

# -----------------------------------------------------------------------------
# URL MAP (for L7)
# -----------------------------------------------------------------------------

resource "google_compute_region_url_map" "url_map" {
  count = var.is_l7 ? 1 : 0

  project         = var.project_id
  name            = "${var.name}-url-map"
  region          = var.region
  default_service = google_compute_region_backend_service.backend.self_link

  dynamic "host_rule" {
    for_each = var.host_rules
    content {
      hosts        = host_rule.value.hosts
      path_matcher = host_rule.value.path_matcher
    }
  }

  dynamic "path_matcher" {
    for_each = var.path_matchers
    content {
      name            = path_matcher.value.name
      default_service = path_matcher.value.default_service

      dynamic "path_rule" {
        # path_rules is optional — coalesce null to [] so for_each never receives null.
        for_each = coalesce(path_matcher.value.path_rules, [])
        content {
          paths   = path_rule.value.paths
          service = path_rule.value.service
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# TARGET PROXY (for L7)
# -----------------------------------------------------------------------------

resource "google_compute_region_target_http_proxy" "http_proxy" {
  count = var.is_l7 && !var.enable_ssl ? 1 : 0

  project = var.project_id
  name    = "${var.name}-http-proxy"
  region  = var.region
  url_map = google_compute_region_url_map.url_map[0].self_link
}

resource "google_compute_region_target_https_proxy" "https_proxy" {
  count = var.is_l7 && var.enable_ssl ? 1 : 0

  project          = var.project_id
  name             = "${var.name}-https-proxy"
  region           = var.region
  url_map          = google_compute_region_url_map.url_map[0].self_link
  ssl_certificates = var.ssl_certificates
}

# -----------------------------------------------------------------------------
# FORWARDING RULE
# -----------------------------------------------------------------------------

resource "google_compute_forwarding_rule" "forwarding_rule" {
  project = var.project_id
  name    = "${var.name}-forwarding-rule"
  region  = var.region

  load_balancing_scheme = var.is_l7 ? "INTERNAL_MANAGED" : "INTERNAL"
  network               = var.network
  subnetwork            = var.subnet
  ip_address            = local.ip_address
  ip_protocol           = "TCP"
  port_range            = var.port_range
  allow_global_access   = var.allow_global_access

  # L7 (is_l7 = true): INTERNAL_MANAGED routes through a target HTTP/S proxy.
  # L4 (is_l7 = false): INTERNAL passthrough forwards directly to the backend
  # service — the forwarding rule must set backend_service, not target.
  target = var.is_l7 ? (
    var.enable_ssl ?
    google_compute_region_target_https_proxy.https_proxy[0].self_link :
    google_compute_region_target_http_proxy.http_proxy[0].self_link
  ) : null
  backend_service = var.is_l7 ? null : google_compute_region_backend_service.backend.self_link

  labels = var.labels
}

# -----------------------------------------------------------------------------
# FIREWALL RULE (for proxy-only subnet)
# -----------------------------------------------------------------------------
#
# firewall_mode mirrors network/tiered-vpc: legacy = tag-targeted VPC rule
# (default), both = VPC rule plus a rule in the VPC's network firewall policy,
# policy = the policy rule only.

resource "google_compute_firewall" "allow_proxy" { #tfsec:ignore:google-compute-no-public-ingress
  count = var.create_firewall_rule && var.firewall_mode != "policy" ? 1 : 0

  project = var.project_id
  name    = "${var.name}-allow-proxy"
  network = var.network

  direction = "INGRESS"
  priority  = var.firewall_priority

  allow {
    protocol = "tcp"
    ports    = [var.backend_port]
  }

  # proxy_only_subnet_ranges are the internal RFC1918 CIDRs of the regional proxy-only
  # subnet, supplied by the caller (see the resource-level tfsec:ignore above).
  source_ranges = var.proxy_only_subnet_ranges
  target_tags   = var.backend_target_tags
}

# Policy rule priorities must be unique within the policy, and several ILBs
# usually share one VPC policy. Unless firewall_policy_rule_priority is set,
# derive a stable priority from the ILB name: 1000 + (first 7 hex digits of
# sha256(name) mod 63000), i.e. 1000-63999, which avoids the 64000-64999 block
# reserved for the network/tiered-vpc tier rules.
locals {
  firewall_policy_rule_priority = coalesce(
    var.firewall_policy_rule_priority,
    1000 + parseint(substr(sha256(var.name), 0, 7), 16) % 63000,
  )
}

# Network firewall policy rules cannot select network tags, so the policy rule
# has no target: it admits the proxy-only subnet ranges on backend_port to
# every instance in the VPC. The source stays the internal proxy-only CIDRs.
resource "google_compute_network_firewall_policy_rule" "allow_proxy" {
  count = var.create_firewall_rule && var.firewall_mode != "legacy" ? 1 : 0

  project         = var.project_id
  firewall_policy = var.firewall_policy
  rule_name       = "${var.name}-allow-proxy"
  description     = "Allow the proxy-only subnet to reach ${var.name} backends"
  priority        = local.firewall_policy_rule_priority
  direction       = "INGRESS"
  action          = "allow"

  match {
    src_ip_ranges = var.proxy_only_subnet_ranges

    layer4_configs {
      ip_protocol = "tcp"
      ports       = [tostring(var.backend_port)]
    }
  }

  lifecycle {
    precondition {
      condition     = var.firewall_policy != null && var.firewall_policy != ""
      error_message = "firewall_policy (the network firewall policy name, e.g. the tiered-vpc firewall_policy_name output) is required when firewall_mode is both or policy and create_firewall_rule is true."
    }
    precondition {
      condition     = local.firewall_policy_rule_priority < 64000 || local.firewall_policy_rule_priority > 64999
      error_message = "firewall_policy_rule_priority must lie outside 64000-64999: that block is reserved for the network/tiered-vpc tier rules in the same policy."
    }
  }
}
