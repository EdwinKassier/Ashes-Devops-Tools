# Centralized DNS resolution for the SRA landing zone.
#
# Inbound and outbound Route 53 Resolver endpoints let on-prem resolvers query
# private hosted zones (inbound) and let VPC workloads forward selected domains
# to on-prem or third-party resolvers (outbound, via FORWARD rules). A Route 53
# Profile carries the DNS configuration and is shared org-wide over RAM so every
# member VPC inherits the same resolver posture. DNS Firewall blocks known-bad
# domains, query logging ships resolver queries to the central Log Archive, and
# optional DNSSEC validation hardens resolution against spoofing.

# --- Resolver endpoints ------------------------------------------------------
# ip_address is a set block with a provider-enforced minimum of 2 entries, so at
# least two subnet_ids must be supplied (one endpoint IP per AZ subnet).

resource "aws_route53_resolver_endpoint" "inbound" {
  name               = "${var.name_prefix}-inbound"
  direction          = "INBOUND"
  security_group_ids = var.security_group_ids

  dynamic "ip_address" {
    for_each = toset(var.subnet_ids)
    content {
      subnet_id = ip_address.value
    }
  }
}

resource "aws_route53_resolver_endpoint" "outbound" {
  name               = "${var.name_prefix}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = var.security_group_ids

  dynamic "ip_address" {
    for_each = toset(var.subnet_ids)
    content {
      subnet_id = ip_address.value
    }
  }
}

# --- Forward rules -----------------------------------------------------------
# Each rule forwards a domain to a set of target resolver IPs via the outbound
# endpoint, then associates the rule with the VPC so workloads pick it up.

resource "aws_route53_resolver_rule" "fwd" {
  for_each = var.forward_rules

  name                 = each.key
  domain_name          = each.value.domain_name
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  dynamic "target_ip" {
    for_each = toset(each.value.target_ips)
    content {
      ip = target_ip.value
    }
  }
}

resource "aws_route53_resolver_rule_association" "fwd" {
  for_each = var.forward_rules

  resolver_rule_id = aws_route53_resolver_rule.fwd[each.key].id
  vpc_id           = var.vpc_id
}

# --- Route 53 Profile (2024+ sharing mechanism) ------------------------------
# The profile bundles the resolver configuration; RAM shares it across the org
# so member accounts consume a single managed DNS posture. External principals
# are disallowed — sharing is scoped to the organization ARN only.

resource "aws_route53profiles_profile" "this" {
  name = "${var.name_prefix}-profile"
}

resource "aws_route53profiles_resource_association" "vpc" {
  name         = "${var.name_prefix}-profile-vpc"
  profile_id   = aws_route53profiles_profile.this.id
  resource_arn = "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:vpc/${var.vpc_id}"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_ram_resource_share" "profile" {
  name                      = "${var.name_prefix}-profile-share"
  allow_external_principals = false
}

resource "aws_ram_resource_association" "profile" {
  resource_arn       = aws_route53profiles_profile.this.arn
  resource_share_arn = aws_ram_resource_share.profile.arn
}

resource "aws_ram_principal_association" "org" {
  principal          = var.org_arn
  resource_share_arn = aws_ram_resource_share.profile.arn
}

# --- DNS Firewall ------------------------------------------------------------
# A block list plus a BLOCK rule wired into a rule group, associated with the
# VPC. firewall_fail_open = DISABLED fails closed so a firewall outage cannot
# silently allow queries to bad domains.

resource "aws_route53_resolver_firewall_domain_list" "blocked" {
  count = var.enable_dns_firewall ? 1 : 0

  name    = "${var.name_prefix}-blocked"
  domains = var.blocked_domains
}

resource "aws_route53_resolver_firewall_rule_group" "this" {
  count = var.enable_dns_firewall ? 1 : 0

  name = "${var.name_prefix}-fw-rg"
}

resource "aws_route53_resolver_firewall_rule" "block" {
  count = var.enable_dns_firewall ? 1 : 0

  name                    = "${var.name_prefix}-block"
  action                  = "BLOCK"
  block_response          = "NXDOMAIN"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.blocked[0].id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this[0].id
  priority                = 100
}

resource "aws_route53_resolver_firewall_rule_group_association" "this" {
  count = var.enable_dns_firewall ? 1 : 0

  name                   = "${var.name_prefix}-fw-assoc"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.this[0].id
  priority               = 101
  vpc_id                 = var.vpc_id
}

resource "aws_route53_resolver_firewall_config" "this" {
  count = var.enable_dns_firewall ? 1 : 0

  resource_id        = var.vpc_id
  firewall_fail_open = "DISABLED"
}

# --- Query logging -> central Log Archive ------------------------------------

resource "aws_route53_resolver_query_log_config" "this" {
  count = var.enable_query_logging ? 1 : 0

  name            = "${var.name_prefix}-qlog"
  destination_arn = var.query_log_destination_arn
}

resource "aws_route53_resolver_query_log_config_association" "this" {
  count = var.enable_query_logging ? 1 : 0

  resolver_query_log_config_id = aws_route53_resolver_query_log_config.this[0].id
  resource_id                  = var.vpc_id
}

# --- DNSSEC validation (optional) --------------------------------------------

resource "aws_route53_resolver_dnssec_config" "this" {
  count = var.enable_dnssec ? 1 : 0

  resource_id = var.vpc_id
}
