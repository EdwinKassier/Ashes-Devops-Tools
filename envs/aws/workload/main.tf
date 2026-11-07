# Phase-3 per-env workload root. Consumes THREE upstream stage contracts:
#   - organization → account_ids (the wrong-account guard on both providers,
#     keyed by local.workload_account_key).
#   - network      → tgw_id + ipam_pool_ids (the spoke attaches to the shared TGW
#     and allocates its CIDR from the region's IPAM pool). OPTIONAL: with
#     enable_network_hub = false the spoke is a standalone VPC (no TGW
#     attachment/routes, literal vpc_cidr, NAT-less private tiers).
#   - security     → log_archive_bucket_name (flow logs, Config, SSM logs).
#
# FAST-style stage contract override: each contract comes from, in order,
#   1. the <layer>_contract variable (tfvars / TFC variable),
#   2. aws.contracts.<layer> in config/landing-zone.yaml,
#   3. the upstream workspace's terraform_remote_state.
# A remote-state read happens ONLY when no contract was supplied (count = 0
# otherwise), so this root can run without the upstream workspace existing.
# It composes the aws-workload stage in a SINGLE workload account. It declares
# ONLY the aws provider — no supabase/vercel (SaaS lives in envs/saas).
locals {
  organization_contract = var.organization_contract != null ? var.organization_contract : local.cfg.organization_contract
  network_contract      = var.network_contract != null ? var.network_contract : local.cfg.network_contract
  # var.log_archive_bucket_name is the legacy single-field form of security_contract.
  security_contract = (
    var.log_archive_bucket_name != null ? { log_archive_bucket_name = var.log_archive_bucket_name } :
    var.security_contract != null ? var.security_contract : local.cfg.security_contract
  )

  read_organization = local.organization_contract == null
  read_network      = var.enable_network_hub && local.network_contract == null
  read_security     = local.security_contract == null
}

data "terraform_remote_state" "aws_organization" {
  count   = local.read_organization ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

data "terraform_remote_state" "aws_network" {
  count   = local.read_network ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces   = { name = var.network_workspace_name }
  }
}

data "terraform_remote_state" "aws_security" {
  count   = local.read_security ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces   = { name = var.security_workspace_name }
  }
}

locals {
  # The upstream contract outputs. A producer state from before the contract
  # output existed (N-1, not yet re-applied) exposes the same keys as individual
  # outputs, so each read falls back to them; that fallback goes at v1.0 with the
  # individual outputs (UPGRADING.md).
  org_remote      = local.read_organization ? try(data.terraform_remote_state.aws_organization[0].outputs.contract, data.terraform_remote_state.aws_organization[0].outputs) : null
  network_remote  = local.read_network ? try(data.terraform_remote_state.aws_network[0].outputs.contract, data.terraform_remote_state.aws_network[0].outputs) : null
  security_remote = local.read_security ? try(data.terraform_remote_state.aws_security[0].outputs.contract, data.terraform_remote_state.aws_security[0].outputs) : null

  # Wrong-account guard for both providers. No try(): a missing account_ids key
  # fails the plan loudly instead of silently dropping the guard.
  workload_account_id = (
    local.read_organization
    ? local.org_remote.account_ids[local.workload_account_key]
    : local.organization_contract.account_ids[local.workload_account_key]
  )

  # Network contract; null / "" in standalone mode (enable_network_hub = false).
  tgw_id = (
    !var.enable_network_hub ? null :
    local.read_network ? local.network_remote.tgw_id : local.network_contract.tgw_id
  )
  ipam_pool_id = (
    !var.enable_network_hub ? "" :
    local.read_network ? local.network_remote.ipam_pool_ids[local.aws_region] : lookup(local.network_contract.ipam_pool_ids, local.aws_region, "")
  )

  # The central log-archive bucket name comes from aws-security (its owner) unless
  # a contract supplies it, so a rename there cannot silently leave this
  # workload writing to a stale bucket.
  log_archive_bucket_name = (
    local.read_security
    ? local.security_remote.log_archive_bucket_name
    : local.security_contract.log_archive_bucket_name
  )
}

module "aws_workload" {
  source = "../../../modules/aws/stages/workload"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  aws_region          = local.aws_region
  aws_enabled_regions = local.aws_enabled_regions
  vpc_cidr            = local.vpc_cidr

  # Spoke is named workload-<environment> (local.environment, see providers.tf)
  # and routes the configured tiers to the shared TGW.
  environment           = local.environment
  tgw_route_tiers       = var.tgw_route_tiers
  tgw_destination_cidrs = var.tgw_destination_cidrs

  # Network contract: attach the spoke to the shared TGW and allocate the VPC
  # CIDR from the region's shared IPAM pool. Standalone (no network hub):
  # tgw_id = null -> no attachment/routes; ipam_pool_id = "" -> literal vpc_cidr.
  tgw_id       = local.tgw_id
  ipam_pool_id = local.ipam_pool_id

  # Flow logs + Config snapshots + Session Manager logs all land in the central
  # log-archive bucket (cross-root naming contract).
  flow_log_destination_arn          = "arn:${local.partition}:s3:::${local.log_archive_bucket_name}"
  log_archive_bucket_name           = local.log_archive_bucket_name
  config_role_arn                   = var.config_role_arn
  create_config_service_linked_role = var.create_config_service_linked_role
  kms_key_arn                       = local.kms_key_arn # kms.tf: created unless supplied
  # A CMK created in this plan has an unknown ARN: let the stage set the
  # default EBS key with a plan-safe count (home region, where the key lives).
  enable_ebs_default_kms_key = local.create_kms_key ? true : null

  # App ingress (local.app_ingress_mode): a public ALB needs a public subnet
  # tier + IGW; a CloudFront VPC origin needs only an attached IGW. Neither is
  # built until there is an ALB (services non-empty).
  enable_public_subnets   = local.app_public_alb && local.apps_enabled
  create_internet_gateway = local.app_vpc_origin && local.apps_enabled
  # The org declarative EC2 policy blocks internet-gateway ingress (VPC BPA) on
  # every VPC, so a public ALB needs this spoke VPC excluded. Requires
  # aws-organization allow_vpc_bpa_exclusions = true (otherwise AWS rejects it).
  enable_vpc_bpa_exclusion = local.app_public_alb && local.apps_enabled

  enable_edge    = var.enable_edge
  workload_roles = var.workload_roles
}

# App ingress mode: internal (default) | public_alb | cloudfront_vpc_origin.
locals {
  app_ingress_mode = coalesce(var.app_ingress_mode, local.cfg.app_ingress_mode, "internal")
  app_public_alb   = local.app_ingress_mode == "public_alb"
  app_vpc_origin   = local.app_ingress_mode == "cloudfront_vpc_origin"
  apps_enabled     = length(local.services) > 0

  # Internet-facing ALB: public tier, open listeners (WAF in front). Otherwise
  # the private tier and the spoke CIDR (CloudFront VPC-origin ENIs live there).
  app_alb_subnet_tier = local.app_public_alb ? "public" : var.app_alb_subnet_tier
  app_alb_ingress_cidrs = (
    length(var.app_alb_ingress_cidrs) > 0 ? var.app_alb_ingress_cidrs :
    local.app_public_alb ? ["0.0.0.0/0"] : []
  )
}

# =============================================================================
# APP SERVICES — the application golden path 
#
# One entry in local.services (var.services, else aws.workload_environments.<env>.services) = an ECR repo, a Fargate service in the spoke's
# private subnets behind the shared internal ALB, least-privilege task roles, a
# KMS-encrypted log group, and optionally a GitHub Actions OIDC deploy role and
# an Aurora PostgreSQL cluster. Default services = {} creates nothing. See
# docs/guides/deploying-a-service.md (AWS section).
# =============================================================================

module "app_services" {
  source = "../../../modules/aws/stages/app-services"

  environment = local.environment
  aws_region  = local.aws_region

  # Placement: the spoke VPC this root just built. Tasks + the internal ALB in
  # the private tier (egress via the TGW to central inspection); Aurora in the
  # isolated tier (no route off the VPC).
  vpc_id              = module.aws_workload.vpc_id
  vpc_cidr            = local.vpc_cidr
  service_subnet_ids  = lookup(module.aws_workload.subnet_ids_by_tier, var.app_service_subnet_tier, [])
  alb_subnet_ids      = lookup(module.aws_workload.subnet_ids_by_tier, local.app_alb_subnet_tier, [])
  database_subnet_ids = lookup(module.aws_workload.subnet_ids_by_tier, var.app_database_subnet_tier, [])
  kms_key_arn         = local.kms_key_arn
  bootstrap_image     = local.app_bootstrap_image

  services = local.services

  enable_github_oidc          = var.enable_github_oidc
  create_github_oidc_provider = var.create_github_oidc_provider
  github_oidc_provider_arn    = var.github_oidc_provider_arn

  alb_internal                   = local.app_public_alb ? false : var.app_alb_internal
  alb_certificate_arn            = var.app_alb_certificate_arn
  alb_ingress_cidrs              = local.app_alb_ingress_cidrs
  alb_enable_deletion_protection = var.app_alb_enable_deletion_protection
  alb_access_logs_bucket         = var.app_alb_access_logs_bucket

  log_retention_days  = var.app_log_retention_days
  enable_alarms       = var.enable_app_alarms
  alarm_sns_topic_arn = var.app_alarm_sns_topic_arn
}

# =============================================================================
# APP INGRESS — public exposure of the shared ALB (app_ingress_mode)
#
#   internal               no public path (default). Reach the ALB from the
#                          spoke / over the TGW.
#   public_alb             the ALB is internet-facing in the public tier (HTTPS
#                          only: app_alb_certificate_arn is required) with a
#                          REGIONAL WAF (AWS Common + KnownBadInputs) unless
#                          enable_app_waf = false.
#   cloudfront_vpc_origin  the ALB stays INTERNAL; CloudFront reaches it through
#                          a VPC origin and serves https://<id>.cloudfront.net
#                          (or app_edge_domain_name) behind a CloudFront WAF.
#                          Zero extra inputs: the zero-touch public path.
# =============================================================================

module "app_edge" {
  source = "../../../modules/aws/security/edge-security"
  count  = local.apps_enabled && (local.app_vpc_origin || (local.app_public_alb && var.enable_app_waf)) ? 1 : 0

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix = "${local.environment}-apps"

  # CloudFront -> VPC origin -> internal ALB.
  enable_edge        = local.app_vpc_origin
  enable_vpc_origin  = local.app_vpc_origin
  vpc_origin_arn     = local.app_vpc_origin ? module.app_services.alb_arn : ""
  origin_domain_name = local.app_vpc_origin ? module.app_services.alb_dns_name : "origin.example.com"
  domain_name        = var.app_edge_domain_name
  # An application, not static content: every method, no caching, all viewer
  # headers/cookies/query strings except Host (the ALB routes on path).
  allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
  cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader

  # Internet-facing ALB -> regional WAF.
  enable_regional_waf       = local.app_public_alb && var.enable_app_waf
  regional_waf_resource_arn = local.app_public_alb ? module.app_services.alb_arn : ""
}

# =============================================================================
# SaaS SECRET BRIDGE
#
# Opt-in. Reads the Supabase outputs from a saas-<name> workspace and writes them
# into an AWS Secrets Manager secret, so an ECS/Fargate task can consume Supabase
# as a managed datastore via its container-secret valueFrom. Default off: no saas
# state is read and nothing is created. See docs/architecture/saas-integration.md.
# =============================================================================

data "terraform_remote_state" "saas" {
  count   = var.enable_saas_secret_bridge ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces   = { name = var.saas_workspace_name }
  }
}

resource "aws_secretsmanager_secret" "saas_bridge" {
  # checkov:skip=CKV2_AWS_57:This secret mirrors Supabase-managed credentials whose
  # lifecycle Supabase owns; rotating a copy here would diverge from the source.
  # Re-apply the bridge to refresh it instead.
  count       = var.enable_saas_secret_bridge ? 1 : 0
  name        = var.saas_secret_name
  description = "Bridged Supabase connection details from ${var.saas_workspace_name}."
  kms_key_id  = local.kms_key_arn
}

# Write-only (aws >= 6.45 switches from secret_string in place): the secret
# version keeps no plaintext in plan or state. Write-only values are not diffed,
# so the saas bridge_version output (saas.bridge_rotation) is the re-push signal;
# a producer that predates that output counts as version 1. The values still
# pass through data.terraform_remote_state.saas, which IS stored in this state
# (docs/known-gaps.md).
resource "aws_secretsmanager_secret_version" "saas_bridge" {
  count     = var.enable_saas_secret_bridge ? 1 : 0
  secret_id = aws_secretsmanager_secret.saas_bridge[0].id
  secret_string_wo = jsonencode({
    api_url           = data.terraform_remote_state.saas[0].outputs.supabase_api_url
    service_role_key  = data.terraform_remote_state.saas[0].outputs.supabase_service_role_key
    database_password = data.terraform_remote_state.saas[0].outputs.supabase_database_password
  })
  secret_string_wo_version = try(tonumber(data.terraform_remote_state.saas[0].outputs.bridge_version), 1)
}

# Grant only the named task roles GetSecretValue on the bridged secret.
resource "aws_secretsmanager_secret_policy" "saas_bridge" {
  count      = var.enable_saas_secret_bridge ? 1 : 0
  secret_arn = aws_secretsmanager_secret.saas_bridge[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowNamedReaders"
      Effect    = "Allow"
      Principal = { AWS = var.saas_secret_reader_arns }
      Action    = "secretsmanager:GetSecretValue"
      Resource  = "*"
    }]
  })
}
