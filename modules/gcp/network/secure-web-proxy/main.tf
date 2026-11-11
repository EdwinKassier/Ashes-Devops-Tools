/**
 * Copyright 2026 Ashes
 *
 * # Secure Web Proxy (preview, opt-in)
 *
 * A regional Secure Web Proxy (Cloud Secure Web Proxy, an Envoy-based egress
 * proxy) with a gateway security policy that allows an FQDN allowlist and
 * denies everything else. Optionally creates the proxy-only subnet it needs
 * and publishes the gateway through a Private Service Connect service
 * attachment, so other VPC networks reach one central proxy through a PSC
 * endpoint each.
 *
 * Explicit mode: clients set HTTP_PROXY / HTTPS_PROXY to the gateway (or PSC
 * endpoint) address. Next-hop mode: the caller adds routes with the gateway
 * address as next hop (same VPC and region only).
 *
 * PREVIEW: not yet validated against a real apply. TLS inspection is not
 * configured, so rules match on the host (SNI / CONNECT target), not on paths
 * of HTTPS requests.
 */

locals {
  create_allowlist = length(var.allowed_fqdns) > 0
}

# Proxy-only subnet: the Envoy proxies run in it. One ACTIVE per network and
# region, shared with regional internal and external application load balancers.
resource "google_compute_subnetwork" "proxy_only" {
  count = var.create_proxy_only_subnet ? 1 : 0

  project       = var.project_id
  name          = "${var.name}-proxy-only"
  region        = var.region
  network       = var.network
  ip_cidr_range = var.proxy_only_subnet_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_network_security_url_lists" "allowlist" {
  count = local.create_allowlist ? 1 : 0

  project     = var.project_id
  name        = "${var.name}-allowlist"
  location    = var.region
  description = "Egress FQDN allowlist for ${var.name}"
  values      = var.allowed_fqdns
}

resource "google_network_security_gateway_security_policy" "this" {
  project     = var.project_id
  name        = "${var.name}-policy"
  location    = var.region
  description = "Egress policy for ${var.name}: allowlisted hosts only"
}

resource "google_network_security_gateway_security_policy_rule" "allowlist" {
  count = local.create_allowlist ? 1 : 0

  project                 = var.project_id
  name                    = "allow-allowlisted-hosts"
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.this.name
  enabled                 = true
  priority                = 1000
  description             = "Allow traffic to the hosts in the ${var.name} allowlist"
  session_matcher         = "inUrlList(host(), '${google_network_security_url_lists.allowlist[0].id}')"
  basic_profile           = "ALLOW"
}

resource "google_network_security_gateway_security_policy_rule" "additional" {
  for_each = var.additional_rules

  project                 = var.project_id
  name                    = each.key
  location                = var.region
  gateway_security_policy = google_network_security_gateway_security_policy.this.name
  enabled                 = each.value.enabled
  priority                = each.value.priority
  description             = each.value.description
  session_matcher         = each.value.session_matcher
  application_matcher     = each.value.application_matcher
  basic_profile           = each.value.action
}

resource "google_network_services_gateway" "this" {
  project      = var.project_id
  name         = var.name
  location     = var.region
  type         = "SECURE_WEB_GATEWAY"
  routing_mode = var.routing_mode
  addresses    = var.address == null ? null : [var.address]
  ports        = var.ports
  network      = var.network
  subnetwork   = var.subnetwork

  gateway_security_policy = google_network_security_gateway_security_policy.this.id
  certificate_urls        = length(var.certificate_urls) > 0 ? var.certificate_urls : null

  # The gateway auto-creates a Cloud Router (and NAT) for its egress; remove it
  # with the last gateway in the region.
  delete_swg_autogen_router_on_destroy = true

  labels = var.labels

  depends_on = [
    google_compute_subnetwork.proxy_only,
    google_network_security_gateway_security_policy_rule.allowlist,
    google_network_security_gateway_security_policy_rule.additional,
  ]
}

# Private Service Connect publishing (opt-in): spokes create an endpoint in
# their own VPC instead of routing to the hub over peering.
resource "google_compute_subnetwork" "psc_nat" {
  count = var.create_service_attachment ? 1 : 0

  project       = var.project_id
  name          = "${var.name}-psc-nat"
  region        = var.region
  network       = var.network
  ip_cidr_range = var.psc_nat_subnet_cidr
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

resource "google_compute_service_attachment" "this" {
  count = var.create_service_attachment ? 1 : 0

  project     = var.project_id
  name        = "${var.name}-psc"
  region      = var.region
  description = "Publishes the ${var.name} Secure Web Proxy to accepted consumer projects"

  target_service        = "//networkservices.googleapis.com/${google_network_services_gateway.this.id}"
  connection_preference = "ACCEPT_MANUAL"
  nat_subnets           = [google_compute_subnetwork.psc_nat[0].id]
  enable_proxy_protocol = false

  dynamic "consumer_accept_lists" {
    for_each = toset(var.consumer_accept_projects)
    content {
      project_id_or_num = consumer_accept_lists.value
      connection_limit  = var.consumer_connection_limit
    }
  }
}
