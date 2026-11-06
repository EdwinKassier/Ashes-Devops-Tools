# aws-workload stage (phase-3)
#
# Thin orchestration wrapper that builds everything a SINGLE workload account
# needs to join the landing zone. It runs entirely in ONE workload account: a
# default `aws` provider for the workload's home region plus a `us_east_1` alias
# (same account) that the optional edge-security module needs for CloudFront/WAF.
#
# NO SaaS composition. Supabase/Vercel workloads live only in envs/saas (Epic I);
# this stage is AWS-native infrastructure only.
#
# Composition:
#   - vpc (spoke)          — a private/isolated/tgw spoke VPC (+ an optional
#                            public tier and internet gateway for an
#                            internet-facing app ALB). CIDR is either the
#                            literal vpc_cidr or allocated from the shared IPAM
#                            pool (ipam_pool_id). Gateway endpoints for s3 +
#                            dynamodb keep that traffic off the TGW (associated
#                            with the module-owned non-public route tables).
#   - spoke routes         — the configured tiers (var.tgw_route_tiers, default
#                            private) route var.tgw_destination_cidrs (default
#                            0.0.0.0/0 -> centralized egress/inspection) to the
#                            shared TGW via the vpc module's `routes` input.
#   - spoke TGW attachment — attaches the spoke VPC to the SHARED transit gateway
#                            (tgw_id, shared with this account via RAM by the
#                            network account). Route-table association/propagation
#                            are managed in the NETWORK account, so both default-
#                            route-table flags are false here.
#   - iam_role             — workload/cross-account roles. Break-glass is OFF: it
#                            belongs in the security/management layer, not per
#                            workload.
#   - account_baseline     — per-account guardrails (default EBS encryption, IAM
#                            password policy).
#   - config_recorder      — the config-org module in recorder_only mode. This is
#                            the workload half of the org Config topology: a local
#                            recorder + delivery channel only; the org aggregator
#                            and conformance packs live in the home account's
#                            aws-config stage. Same module, recorder-only mode —
#                            NOT a separate module.
#   - systems_manager      — optional (enable_ssm, default true): Session Manager
#                            preferences, patch baseline, inventory.
#   - edge_security         — optional (enable_edge, default false): per-workload
#                            CloudFront + WAF edge. Uses the us_east_1 alias.

# ---------------------------------------------------------------------------
# Spoke VPC — private/isolated/tgw tiers; CIDR literal or from shared IPAM
# ---------------------------------------------------------------------------

# Boundary propagation (tfc-oidc-baseline): the workload-account tfc-apply role
# may only create roles that carry its own permissions boundary.
data "aws_caller_identity" "current" {
  count = var.tfc_apply_boundary_policy_name != null ? 1 : 0
}

data "aws_partition" "current" {
  count = var.tfc_apply_boundary_policy_name != null ? 1 : 0
}

locals {
  # Real AWS always returns a 12-digit account and an aws* partition; under
  # mock_provider these data sources return random strings the provider's ARN
  # validator rejects, so a malformed identity yields no boundary rather than
  # failing every mocked plan downstream (tests override the data sources).
  boundary_partition = try(data.aws_partition.current[0].partition, null)
  boundary_account   = try(data.aws_caller_identity.current[0].account_id, null)
  permissions_boundary_arn = (
    var.tfc_apply_boundary_policy_name != null && can(regex("^aws(-[a-z]+)*$", local.boundary_partition)) && can(regex("^[0-9]{12}$", local.boundary_account))
    ? "arn:${local.boundary_partition}:iam::${local.boundary_account}:policy/${var.tfc_apply_boundary_policy_name}"
    : null
  )

  # Optional public ingress tier (enable_public_subnets): an internet-facing
  # ALB's subnets. Its route tables default-route to the internet gateway; the
  # private/isolated/tgw tiers are unchanged (still egress via the TGW, or none).
  # A caller-supplied "public" tier in var.subnets wins over the built-in one.
  subnets = merge(
    var.enable_public_subnets ? { public = { newbits = 8, number_offset = 24, public = true } } : {},
    var.subnets,
  )
  # An IGW is needed by the public tier, and attached (with no routes) for a
  # CloudFront VPC origin, which AWS requires the origin VPC to have.
  create_internet_gateway = var.enable_public_subnets || var.create_internet_gateway

  # VPC / attachment name: explicit var.name, else workload-<environment>, else
  # the legacy "workload".
  name = coalesce(var.name, var.environment != null ? "workload-${var.environment}" : "workload")

  # Spoke routing contract: every tier in tgw_route_tiers sends each
  # tgw_destination_cidrs entry to the shared TGW. The target is read from the
  # attachment resource so the routes are only created once the VPC is attached
  # (a VPC route to a TGW is rejected before the attachment exists).
  # Standalone mode (tgw_id = null): no attachment, so no TGW routes at all.
  routed_tiers = var.tgw_id == null ? [] : var.tgw_route_tiers
  spoke_routes = {
    for tier in local.routed_tiers : tier => [
      for cidr in var.tgw_destination_cidrs : {
        destination_cidr_block = cidr
        transit_gateway_id     = aws_ec2_transit_gateway_vpc_attachment.spoke[0].transit_gateway_id
      }
    ]
  }
}

module "vpc" {
  source = "../../network/vpc"

  name                     = local.name
  cidr_block               = var.vpc_cidr
  region                   = var.aws_region
  availability_zones       = var.availability_zones
  az_count                 = var.az_count
  subnets                  = local.subnets
  create_internet_gateway  = local.create_internet_gateway
  flow_log_destination_arn = var.flow_log_destination_arn
  ipam_pool_id             = var.ipam_pool_id
  gateway_endpoints        = ["s3", "dynamodb"]
  routes                   = local.spoke_routes
  tags                     = var.tags
}

# ---------------------------------------------------------------------------
# Spoke transit-gateway attachment
#
# Attaches the spoke VPC to the SHARED transit gateway (var.tgw_id) that the
# network account shared into this account over RAM. This attachment resource is
# created IN THE WORKLOAD ACCOUNT (that is where the VPC and its tgw-tier subnets
# live); the network account owns the TGW and manages its route-table
# association/propagation. So both default-route-table flags are false here —
# the workload never touches the hub's segment routing.
#
# Skipped entirely when tgw_id = null (standalone spoke, no aws-network layer).
# ---------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  count = var.tgw_id == null ? 0 : 1

  transit_gateway_id = var.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.subnet_ids_by_tier["tgw"]

  # Route-table association + propagation are managed by the network account on
  # the segmented hub; never fall back to the TGW default route tables here.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, { Name = "${local.name}-spoke" })
}

moved {
  from = aws_ec2_transit_gateway_vpc_attachment.spoke
  to   = aws_ec2_transit_gateway_vpc_attachment.spoke[0]
}

# ---------------------------------------------------------------------------
# IAM roles — workload / cross-account. Break-glass lives in the security layer.
# ---------------------------------------------------------------------------

module "iam_role" {
  source = "../../iam/iam-role"

  roles = var.workload_roles
  # Default boundary for roles that do not set their own permissions_boundary.
  permissions_boundary_arn = local.permissions_boundary_arn

  # Break-glass is an org-level emergency-access construct owned by the
  # security/management layer, not replicated into every workload account.
  enable_break_glass = false
}

# ---------------------------------------------------------------------------
# Account baseline — default EBS encryption + IAM password policy
# ---------------------------------------------------------------------------

module "account_baseline" {
  source = "../../governance/account-baseline"

  aws_enabled_regions = var.aws_enabled_regions
  # enable_ebs_default_kms_key set => the stage owns the default-key setting
  # (below); null => legacy: the baseline sets it in every enabled region when
  # kms_key_arn is non-empty (a for_each that needs a plan-known literal ARN).
  kms_key_arn = var.enable_ebs_default_kms_key != null ? "" : var.kms_key_arn
}

# Default EBS key in the HOME region when the caller says so explicitly — the
# for_each-free path for a CMK created in the same plan (unknown ARN). A
# regional CMK can only be the default key of its own region.
resource "aws_ebs_default_kms_key" "home" {
  count   = var.enable_ebs_default_kms_key == true ? 1 : 0
  key_arn = var.kms_key_arn
}

# ---------------------------------------------------------------------------
# Config recorder — the org Config topology's workload half (recorder-only)
#
# The SAME config-org module the home-account aws-config stage uses, invoked in
# recorder_only mode: a per-Region recorder + delivery channel + recorder status
# only. The org aggregator and conformance packs are skipped (they belong to the
# home account), so aggregator_role_arn is unused and left empty.
# ---------------------------------------------------------------------------

module "config_recorder" {
  source = "../../security/config-org"

  recorder_only = true

  aws_enabled_regions        = var.aws_enabled_regions
  config_role_arn            = var.config_role_arn
  create_service_linked_role = var.create_config_service_linked_role
  aggregator_role_arn        = "" # unused in recorder_only mode
  log_archive_bucket         = var.log_archive_bucket_name
}

# ---------------------------------------------------------------------------
# Systems Manager — optional (Session Manager, patch baseline, inventory)
# ---------------------------------------------------------------------------

module "systems_manager" {
  # checkov:skip=CKV_AWS_112:The Session Manager document IS KMS-encrypted — it
  #   sets kmsKeyId = var.kms_key_arn with cloudWatch/s3 encryption enabled.
  #   Checkov statically resolves the stage's empty-string kms_key_arn DEFAULT and
  #   flags the document as unencrypted, but the enable_ssm validation rejects
  #   enable_ssm=true with an empty kms_key_arn, so that unencrypted state is
  #   unreachable at apply. The shared systems-manager module (and aws-security's
  #   use of it, which passes a real key) is unaffected — this skip is scoped to
  #   this stage's composition only.
  source = "../../ops/systems-manager"
  count  = var.enable_ssm ? 1 : 0

  log_bucket_name = var.log_archive_bucket_name
  kms_key_id      = var.kms_key_arn
}

# ---------------------------------------------------------------------------
# Edge security — optional per-workload CloudFront + WAF (us-east-1)
# ---------------------------------------------------------------------------

module "edge_security" {
  source = "../../security/edge-security"
  count  = var.enable_edge ? 1 : 0

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  enable_edge        = true
  name_prefix        = var.edge_name_prefix
  origin_domain_name = var.edge_origin_domain_name
}

# ---------------------------------------------------------------------------
# VPC Block Public Access exclusion (public app ingress only)
# ---------------------------------------------------------------------------
# The org declarative EC2 policy enforces VPC BPA (block internet-gateway
# ingress) on every member VPC. An internet-facing ALB therefore receives no
# traffic unless THIS VPC is excluded. The exclusion is scoped to the spoke VPC
# only and is created solely when the workload root selects public_alb ingress;
# AWS accepts it only if aws-organization allows exclusions
# (allow_vpc_bpa_exclusions = true).
resource "aws_vpc_block_public_access_exclusion" "public_ingress" {
  count = var.enable_vpc_bpa_exclusion ? 1 : 0

  vpc_id                          = module.vpc.vpc_id
  internet_gateway_exclusion_mode = "allow-bidirectional"

  tags = merge(var.tags, { Name = "${local.name}-public-ingress" })
}
