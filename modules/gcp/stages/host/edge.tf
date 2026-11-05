# Host stage: edge and ingress (Cloud Armor, CDN, API Gateway, internal LBs).
# Part of modules/gcp/stages/host.

# =============================================================================
# EDGE SECURITY (Cloud Armor WAF)
# =============================================================================

module "cloud_armor" {
  source = "../../network/cloud-armor"
  count  = var.enable_cloud_armor ? 1 : 0

  project_id                 = var.project_id
  policy_name                = "${var.project_prefix}-security-policy"
  description                = "WAF security policy for ${var.project_prefix}"
  enable_owasp_rules         = var.enable_owasp_rules
  enable_adaptive_protection = var.enable_adaptive_protection
  enable_log4j_protection    = var.enable_log4j_protection
  owasp_sensitivity          = var.owasp_sensitivity
  custom_rules               = var.cloud_armor_custom_rules
}

# =============================================================================
# CONTENT DELIVERY (CDN + Global Load Balancer)
# =============================================================================

module "cdn" {
  source = "../../network/cdn"
  count  = var.enable_cdn ? 1 : 0

  project_id           = var.project_id
  lb_name              = "${var.project_prefix}-cdn"
  domains              = var.cdn_domains
  enable_cdn           = true
  enable_http_redirect = var.cdn_enable_http_redirect
  security_policy      = var.enable_cloud_armor ? module.cloud_armor[0].policy_self_link : null
  backend_groups       = var.cdn_backend_groups
  cdn_policy           = var.cdn_policy
}

# =============================================================================
# API GATEWAY
# =============================================================================

module "api_gateway" {
  source = "../../network/api-gateway"
  count  = var.enable_api_gateway ? 1 : 0

  project_id            = var.project_id
  region                = var.region
  api_id                = "${var.project_prefix}-api"
  display_name          = var.api_gateway_display_name
  gateway_id            = "${var.project_prefix}-gateway"
  gateway_display_name  = "${var.api_gateway_display_name} Gateway"
  service_account_email = var.api_gateway_service_account
  managed_service_ids   = var.api_gateway_managed_services
  openapi_spec          = var.api_gateway_openapi_spec
  labels                = var.labels
}

# =============================================================================
# INTERNAL LOAD BALANCERS
# =============================================================================

module "internal_load_balancers" {
  source   = "../../network/internal-lb"
  for_each = var.internal_load_balancers

  project_id = var.project_id
  name       = each.key
  region     = each.value.region
  network    = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link
  subnet     = each.value.subnet

  is_l7      = try(each.value.is_l7, true)
  port_range = try(each.value.port_range, "80")
  backends   = each.value.backends

  # Health check
  health_check_type         = try(each.value.health_check_type, "HTTP")
  health_check_port         = try(each.value.health_check_port, 80)
  health_check_request_path = try(each.value.health_check_request_path, "/health")

  # Optional settings
  allow_global_access = try(each.value.allow_global_access, false)
  enable_ssl          = try(each.value.enable_ssl, false)
  ssl_certificates    = try(each.value.ssl_certificates, [])
  session_affinity    = try(each.value.session_affinity, "NONE")
  enable_logging      = try(each.value.enable_logging, true)

  # Firewall
  create_firewall_rule     = try(each.value.create_firewall_rule, true)
  proxy_only_subnet_ranges = try(each.value.proxy_only_subnet_ranges, [])
  backend_target_tags      = try(each.value.backend_target_tags, [])
  backend_port             = try(each.value.backend_port, 80)

  labels = try(each.value.labels, {})
}
