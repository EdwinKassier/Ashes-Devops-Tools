# Data-driven VPC for the SRA landing zone.
#
# Subnets are NOT enumerated by a fixed role list. Instead the caller describes
# tiers in var.subnets (tier -> {newbits, number_offset, public}) and the module
# builds one subnet per tier per AZ, carving CIDRs from the VPC supernet with
# cidrsubnet(). This keeps the module composable: NAT/egress and firewall
# subnets, route tables, and the transit gateway wiring are layered on by the
# aws-network-hub STAGE, not by this leaf module.
#
# IPAM vs cidrsubnet, resolved:
#   When ipam_pool_id is set, the VPC's real CIDR is allocated by IPAM and is
#   unknown at plan time, so cidrsubnet() on it would fail under mock_provider.
#   To keep subnet math deterministic and testable, local.vpc_cidr is ALWAYS
#   var.cidr_block. The caller therefore passes the intended CIDR (the same value
#   IPAM will allocate) even when ipam_pool_id drives the VPC allocation;
#   ipam_pool_id + netmask_length only control how the VPC itself obtains its
#   block. cidr_block is always required for the subnet layout.

locals {
  vpc_cidr = var.cidr_block

  # AZs actually used, limited to az_count.
  azs = slice(var.availability_zones, 0, var.az_count)

  # Flatten (tier x az) into a single map keyed "tier-az". Each entry carries
  # the tier config plus the AZ index, used as the cidrsubnet netnum offset.
  subnet_defs = merge([
    for tier, cfg in var.subnets : {
      for i, az in local.azs :
      "${tier}-${az}" => {
        tier  = tier
        az    = az
        index = i
        cfg   = cfg
      }
    }
  ]...)
}

resource "aws_vpc" "this" {
  # When using IPAM, the CIDR is allocated from the pool (ipv4_ipam_pool_id +
  # ipv4_netmask_length). Otherwise a literal cidr_block is used. Exactly one
  # path is active.
  ipv4_ipam_pool_id   = var.ipam_pool_id != "" ? var.ipam_pool_id : null
  ipv4_netmask_length = var.ipam_pool_id != "" ? var.netmask_length : null
  cidr_block          = var.ipam_pool_id == "" ? var.cidr_block : null

  assign_generated_ipv6_cidr_block = var.enable_ipv6
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = { Name = var.name }
}

resource "aws_subnet" "this" {
  for_each = local.subnet_defs

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value.az
  cidr_block        = cidrsubnet(local.vpc_cidr, each.value.cfg.newbits, each.value.cfg.number_offset + each.value.index)

  # Auto-assigning public IPs is the intended behaviour of a tier explicitly
  # declared public = true (e.g. the public/ingress tier). Non-public tiers
  # leave this false, so only tiers the caller opts into as public get one.
  map_public_ip_on_launch = try(each.value.cfg.public, false) #tfsec:ignore:aws-ec2-no-public-ip-subnet

  tags = {
    Name = "${var.name}-${each.value.tier}-${each.value.az}"
    Tier = each.value.tier
  }
}

# Restrict the default security group to deny all traffic (tfsec/CIS): declaring
# the resource with no ingress/egress rules removes AWS's permissive defaults.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
}

# VPC flow logs to the central log archive (tfsec aws-ec2-require-vpc-flow-logs).
resource "aws_flow_log" "this" {
  log_destination      = var.flow_log_destination_arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.this.id
}

# Gateway endpoints (S3, DynamoDB) keep that traffic on the AWS backbone.
resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_endpoints)

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type = "Gateway"
}
