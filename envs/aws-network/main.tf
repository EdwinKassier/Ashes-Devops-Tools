# Phase-2 network root. Reads the phase-1 aws-organization root's remote state
# (credential-free config — the actual read happens with cloud creds at plan
# time) and composes the aws-network-hub stage: the centralized network hub
# (transit gateway, IPAM, inspection + egress VPCs, Route 53 resolver profile,
# interface endpoints) in the network account. It is a CONSUMER of the
# organization cross-root contract (organization_id, management_account_id,
# account_role_arns) and re-exports the network cross-root contract for
# downstream app roots.
data "terraform_remote_state" "aws_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

locals {
  # Org ARN for RAM org-wide sharing, built from existing organization outputs
  # (management account id + org id) so no extra remote-state dependency is
  # needed just to obtain the ARN.
  org_arn = "arn:aws:organizations::${data.terraform_remote_state.aws_organization.outputs.management_account_id}:organization/${data.terraform_remote_state.aws_organization.outputs.organization_id}"
}

module "aws_network_hub" {
  source = "../../modules/stages/aws-network-hub"

  org_id  = data.terraform_remote_state.aws_organization.outputs.organization_id
  org_arn = local.org_arn

  aws_region          = var.aws_region
  aws_enabled_regions = var.aws_enabled_regions

  top_cidr           = var.top_cidr
  regional_cidrs     = var.regional_cidrs
  inspection_cidr    = var.inspection_cidr
  egress_cidr        = var.egress_cidr
  availability_zones = var.availability_zones
  az_count           = var.az_count

  flow_log_destination_arn = "arn:aws:s3:::${var.log_archive_bucket_name}"
  log_bucket_name          = var.log_archive_bucket_name

  private_hosted_zone_name       = var.private_hosted_zone_name
  enable_network_firewall        = var.enable_network_firewall
  enable_network_access_analyzer = var.enable_network_access_analyzer
}
