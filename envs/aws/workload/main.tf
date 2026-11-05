# Phase-3 per-env workload root. Reads TWO upstream roots' remote state:
#   - aws_organization → account_role_arns (the per-env workload account role the
#     providers assume, keyed by var.workload_account_key).
#   - aws_network      → the network cross-root contract (tgw_id + ipam_pool_ids)
#     the spoke VPC attaches to / allocates its CIDR from.
# It composes the aws-workload stage in a SINGLE workload account. It declares
# ONLY the aws provider — no supabase/vercel (SaaS lives in envs/saas).
data "terraform_remote_state" "aws_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

data "terraform_remote_state" "aws_network" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces   = { name = var.network_workspace_name }
  }
}

data "terraform_remote_state" "aws_security" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces   = { name = var.security_workspace_name }
  }
}

locals {
  # Source the central log-archive bucket name from aws-security (its owner), so a
  # rename/rotation there cannot silently leave this workload writing flow logs,
  # Config snapshots and Session Manager logs to a stale bucket (audit M7).
  # var.log_archive_bucket_name, if set, overrides for out-of-band setups.
  log_archive_bucket_name = coalesce(var.log_archive_bucket_name, data.terraform_remote_state.aws_security.outputs.log_archive_bucket_name)
}

module "aws_workload" {
  source = "../../../modules/aws/stages/workload"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  aws_region          = var.aws_region
  aws_enabled_regions = var.aws_enabled_regions
  vpc_cidr            = var.vpc_cidr

  # Spoke is named workload-<environment> (local.environment, see providers.tf)
  # and routes the configured tiers to the shared TGW.
  environment           = local.environment
  tgw_route_tiers       = var.tgw_route_tiers
  tgw_destination_cidrs = var.tgw_destination_cidrs

  # Network cross-root contract: attach the spoke to the shared TGW and allocate
  # the VPC CIDR from the region's shared IPAM pool.
  tgw_id       = data.terraform_remote_state.aws_network.outputs.tgw_id
  ipam_pool_id = data.terraform_remote_state.aws_network.outputs.ipam_pool_ids[var.aws_region]

  # Flow logs + Config snapshots + Session Manager logs all land in the central
  # log-archive bucket (cross-root naming contract).
  flow_log_destination_arn = "arn:aws:s3:::${local.log_archive_bucket_name}"
  log_archive_bucket_name  = local.log_archive_bucket_name
  config_role_arn          = var.config_role_arn
  kms_key_arn              = var.kms_key_arn

  enable_edge    = var.enable_edge
  workload_roles = var.workload_roles
}

# =============================================================================
# APP SERVICES — the application golden path (audit: Boilerplate H)
#
# One entry in var.services = an ECR repo, a Fargate service in the spoke's
# private subnets behind the shared internal ALB, least-privilege task roles, a
# KMS-encrypted log group, and optionally a GitHub Actions OIDC deploy role and
# an Aurora PostgreSQL cluster. Default services = {} creates nothing. See
# docs/guides/deploying-a-service.md (AWS section).
# =============================================================================

module "app_services" {
  source = "../../../modules/aws/stages/app-services"

  environment = local.environment
  aws_region  = var.aws_region

  # Placement: the spoke VPC this root just built. Tasks + the internal ALB in
  # the private tier (egress via the TGW to central inspection); Aurora in the
  # isolated tier (no route off the VPC).
  vpc_id              = module.aws_workload.vpc_id
  vpc_cidr            = var.vpc_cidr
  service_subnet_ids  = lookup(module.aws_workload.subnet_ids_by_tier, var.app_service_subnet_tier, [])
  alb_subnet_ids      = lookup(module.aws_workload.subnet_ids_by_tier, var.app_alb_subnet_tier, [])
  database_subnet_ids = lookup(module.aws_workload.subnet_ids_by_tier, var.app_database_subnet_tier, [])
  kms_key_arn         = var.kms_key_arn

  services = var.services

  enable_github_oidc          = var.enable_github_oidc
  create_github_oidc_provider = var.create_github_oidc_provider
  github_oidc_provider_arn    = var.github_oidc_provider_arn

  alb_internal                   = var.app_alb_internal
  alb_certificate_arn            = var.app_alb_certificate_arn
  alb_ingress_cidrs              = var.app_alb_ingress_cidrs
  alb_enable_deletion_protection = var.app_alb_enable_deletion_protection
  alb_access_logs_bucket         = var.app_alb_access_logs_bucket

  log_retention_days  = var.app_log_retention_days
  enable_alarms       = var.enable_app_alarms
  alarm_sns_topic_arn = var.app_alarm_sns_topic_arn
}

# =============================================================================
# SaaS SECRET BRIDGE (audit H9, hybrid option C — AWS counterpart)
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
    organization = var.tfc_organization
    workspaces   = { name = var.saas_workspace_name }
  }
}

resource "aws_secretsmanager_secret" "saas_bridge" {
  # checkov:skip=CKV_AWS_149:Encrypted with the workload CMK (var.kms_key_arn) when
  # supplied, otherwise the account's default aws/secretsmanager key. Encryption at
  # rest is always in effect.
  # checkov:skip=CKV2_AWS_57:This secret mirrors Supabase-managed credentials whose
  # lifecycle Supabase owns; rotating a copy here would diverge from the source.
  # Re-apply the bridge to refresh it instead.
  count       = var.enable_saas_secret_bridge ? 1 : 0
  name        = var.saas_secret_name
  description = "Bridged Supabase connection details from ${var.saas_workspace_name} (audit H9)."
  kms_key_id  = var.kms_key_arn != "" ? var.kms_key_arn : null
}

resource "aws_secretsmanager_secret_version" "saas_bridge" {
  count     = var.enable_saas_secret_bridge ? 1 : 0
  secret_id = aws_secretsmanager_secret.saas_bridge[0].id
  secret_string = jsonencode({
    api_url           = data.terraform_remote_state.saas[0].outputs.supabase_api_url
    service_role_key  = data.terraform_remote_state.saas[0].outputs.supabase_service_role_key
    database_password = data.terraform_remote_state.saas[0].outputs.supabase_database_password
  })
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
