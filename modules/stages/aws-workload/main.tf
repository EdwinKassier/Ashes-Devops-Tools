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
#   - vpc (spoke)          — a private/isolated/tgw spoke VPC. CIDR is either the
#                            literal vpc_cidr or allocated from the shared IPAM
#                            pool (ipam_pool_id). Gateway endpoints for s3 +
#                            dynamodb keep that traffic off the TGW.
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

module "vpc" {
  source = "../../aws/vpc"

  name                     = "workload"
  cidr_block               = var.vpc_cidr
  region                   = var.aws_region
  availability_zones       = var.availability_zones
  az_count                 = var.az_count
  subnets                  = var.subnets
  flow_log_destination_arn = var.flow_log_destination_arn
  ipam_pool_id             = var.ipam_pool_id
  gateway_endpoints        = ["s3", "dynamodb"]
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
# ---------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  transit_gateway_id = var.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.subnet_ids_by_tier["tgw"]

  # Route-table association + propagation are managed by the network account on
  # the segmented hub; never fall back to the TGW default route tables here.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "workload-spoke" }
}

# ---------------------------------------------------------------------------
# IAM roles — workload / cross-account. Break-glass lives in the security layer.
# ---------------------------------------------------------------------------

module "iam_role" {
  source = "../../aws/iam-role"

  roles = var.workload_roles

  # Break-glass is an org-level emergency-access construct owned by the
  # security/management layer, not replicated into every workload account.
  enable_break_glass = false
}

# ---------------------------------------------------------------------------
# Account baseline — default EBS encryption + IAM password policy
# ---------------------------------------------------------------------------

module "account_baseline" {
  source = "../../aws/account-baseline"

  aws_enabled_regions = var.aws_enabled_regions
  kms_key_arn         = var.kms_key_arn
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
  source = "../../aws/config-org"

  recorder_only = true

  aws_enabled_regions = var.aws_enabled_regions
  config_role_arn     = var.config_role_arn
  aggregator_role_arn = "" # unused in recorder_only mode
  log_archive_bucket  = var.log_archive_bucket_name
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
  source = "../../aws/systems-manager"
  count  = var.enable_ssm ? 1 : 0

  log_bucket_name = var.log_archive_bucket_name
  kms_key_id      = var.kms_key_arn
}

# ---------------------------------------------------------------------------
# Edge security — optional per-workload CloudFront + WAF (us-east-1)
# ---------------------------------------------------------------------------

module "edge_security" {
  source = "../../aws/edge-security"
  count  = var.enable_edge ? 1 : 0

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  enable_edge        = true
  name_prefix        = var.edge_name_prefix
  origin_domain_name = var.edge_origin_domain_name
}
