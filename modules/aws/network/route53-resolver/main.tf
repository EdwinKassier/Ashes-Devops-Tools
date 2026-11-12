# Centralized DNS resolution for the SRA landing zone.
#
# A Route 53 Profile carries the DNS configuration (DNS Firewall rule group,
# FORWARD rules and private hosted zones such as the central interface endpoint
# zones) and is shared org-wide over RAM. Each member VPC associates the shared
# profile (aws_route53profiles_association, in the VPC's own account) and
# inherits that configuration. Inbound and outbound Route 53 Resolver endpoints
# are opt-in (enable_resolver_endpoints): on-premises resolvers query private
# hosted zones through the inbound endpoint, and FORWARD rules send selected
# domains to on-premises or third-party resolvers through the outbound one.
# Query logging ships resolver queries to the central Log Archive, and optional
# DNSSEC validation hardens resolution against spoofing.

# --- Resolver endpoints (opt-in) ---------------------------------------------
# ip_address is a set block with a provider-enforced minimum of 2 entries, so at
# least two subnet_ids must be supplied (one endpoint IP per AZ subnet). The
# endpoint security groups are ForceNew in the provider.

locals {
  forward_target_cidrs        = sort(distinct(flatten([for r in values(var.forward_rules) : [for ip in r.target_ips : "${ip}/32"]])))
  resolver_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : aws_security_group.resolver[*].id
}

resource "aws_security_group" "resolver" {
  count = var.enable_resolver_endpoints && length(var.security_group_ids) == 0 ? 1 : 0

  name_prefix = "${var.name_prefix}-resolver-"
  description = "Route 53 Resolver endpoints: DNS from allowed_cidrs, DNS out to the forward targets."
  vpc_id      = var.vpc_id

  ingress {
    description = "DNS over UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "DNS over TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Egress is DNS to the forward_rules target IPs only. Replies to inbound
  # queries need no egress rule (security groups are stateful). Attribute
  # syntax, so an empty list removes the AWS default allow-all egress rule
  # (an omitted egress block would leave it in place).
  egress = [
    for proto in(length(local.forward_target_cidrs) > 0 ? ["tcp", "udp"] : []) : {
      description      = "DNS over ${upper(proto)} to forward targets"
      from_port        = 53
      to_port          = 53
      protocol         = proto
      cidr_blocks      = local.forward_target_cidrs
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  tags = merge(var.tags, { Name = "${var.name_prefix}-resolver" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_resolver_endpoint" "inbound" {
  count = var.enable_resolver_endpoints ? 1 : 0

  name               = "${var.name_prefix}-inbound"
  direction          = "INBOUND"
  security_group_ids = local.resolver_security_group_ids

  dynamic "ip_address" {
    for_each = toset(var.subnet_ids)
    content {
      subnet_id = ip_address.value
    }
  }

  tags = var.tags
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count = var.enable_resolver_endpoints ? 1 : 0

  name               = "${var.name_prefix}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = local.resolver_security_group_ids

  dynamic "ip_address" {
    for_each = toset(var.subnet_ids)
    content {
      subnet_id = ip_address.value
    }
  }

  tags = var.tags
}

moved {
  from = aws_route53_resolver_endpoint.inbound
  to   = aws_route53_resolver_endpoint.inbound[0]
}

moved {
  from = aws_route53_resolver_endpoint.outbound
  to   = aws_route53_resolver_endpoint.outbound[0]
}

# --- Forward rules -----------------------------------------------------------
# Each rule forwards a domain to a set of target resolver IPs via the outbound
# endpoint, then associates the rule with the VPC so workloads pick it up.

resource "aws_route53_resolver_rule" "fwd" {
  for_each = var.forward_rules

  name                 = each.key
  domain_name          = each.value.domain_name
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = toset(each.value.target_ips)
    content {
      ip = target_ip.value
    }
  }

  tags = var.tags
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
  tags = var.tags
}

# Profile resources: what every VPC that associates the profile inherits. The
# Route 53 Profiles API accepts a private hosted zone, a DNS Firewall rule
# group, a Resolver rule or an interface VPC endpoint here. A VPC is not a
# profile resource: VPCs join with aws_route53profiles_association.
resource "aws_route53profiles_resource_association" "firewall" {
  count = var.enable_dns_firewall ? 1 : 0

  name                = "${var.name_prefix}-profile-dns-firewall"
  profile_id          = aws_route53profiles_profile.this.id
  resource_arn        = aws_route53_resolver_firewall_rule_group.this[0].arn
  resource_properties = jsonencode({ priority = 101 })
}

resource "aws_route53profiles_resource_association" "rules" {
  for_each = var.forward_rules

  name         = "${var.name_prefix}-profile-rule-${each.key}"
  profile_id   = aws_route53profiles_profile.this.id
  resource_arn = aws_route53_resolver_rule.fwd[each.key].arn
}

resource "aws_route53profiles_resource_association" "hosted_zones" {
  for_each = var.profile_hosted_zone_arns

  name         = "${var.name_prefix}-profile-phz-${each.key}"
  profile_id   = aws_route53profiles_profile.this.id
  resource_arn = each.value
}

resource "aws_ram_resource_share" "profile" {
  name                      = "${var.name_prefix}-profile-share"
  allow_external_principals = false
  tags                      = var.tags
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
  tags    = var.tags
}

resource "aws_route53_resolver_firewall_rule_group" "this" {
  count = var.enable_dns_firewall ? 1 : 0

  name = "${var.name_prefix}-fw-rg"
  tags = var.tags
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
  tags                   = var.tags
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
  tags            = var.tags
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
