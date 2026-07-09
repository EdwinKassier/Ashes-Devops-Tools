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

module "aws_workload" {
  source = "../../modules/stages/aws-workload"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  aws_region          = var.aws_region
  aws_enabled_regions = var.aws_enabled_regions
  vpc_cidr            = var.vpc_cidr

  # Network cross-root contract: attach the spoke to the shared TGW and allocate
  # the VPC CIDR from the region's shared IPAM pool.
  tgw_id       = data.terraform_remote_state.aws_network.outputs.tgw_id
  ipam_pool_id = data.terraform_remote_state.aws_network.outputs.ipam_pool_ids[var.aws_region]

  # Flow logs + Config snapshots + Session Manager logs all land in the central
  # log-archive bucket (cross-root naming contract).
  flow_log_destination_arn = "arn:aws:s3:::${var.log_archive_bucket_name}"
  log_archive_bucket_name  = var.log_archive_bucket_name
  config_role_arn          = var.config_role_arn
  kms_key_arn              = var.kms_key_arn

  enable_edge    = var.enable_edge
  workload_roles = var.workload_roles
}
