# Phase-2 network root. Reads the phase-1 aws-organization root's remote state
# (credential-free config — the actual read happens with cloud creds at plan
# time) and composes the aws-network-hub stage: the centralized network hub
# (transit gateway, IPAM, inspection + egress VPCs, Route 53 resolver profile,
# interface endpoints) in the network account. It is a CONSUMER of the
# organization cross-root contract (organization_id, management_account_id,
# account_role_arns) and re-exports the network cross-root contract for
# downstream app roots.
# Stage contract override (FAST-style): var.organization_contract (or
# aws.contracts.organization in config/landing-zone.yaml) replaces this read —
# count = 0 — so the root can plan without the aws-organization workspace.
locals {
  organization_contract = var.organization_contract != null ? var.organization_contract : local.cfg.organization_contract
  read_organization     = local.organization_contract == null
  # The upstream contract output. A producer state from before the contract
  # output existed (N-1, not yet re-applied) exposes the same keys as
  # individual outputs, so the read falls back to them; that fallback goes at
  # v1.0 with the individual outputs (UPGRADING.md).
  org_remote = local.read_organization ? try(data.terraform_remote_state.aws_organization[0].outputs.contract, data.terraform_remote_state.aws_organization[0].outputs) : null
  # The organization contract, whichever source supplied it, as one type (the
  # variable's). Fields this root needs are read strictly (a missing key fails
  # the plan); the rest default.
  org = local.read_organization ? {
    organization_id       = local.org_remote.organization_id
    organization_root_id  = try(local.org_remote.organization_root_id, null)
    management_account_id = local.org_remote.management_account_id
    ou_ids                = try(tomap(local.org_remote.ou_ids), {})
    account_ids           = tomap(local.org_remote.account_ids)
    account_role_arns     = try(tomap(local.org_remote.account_role_arns), {})
  } : local.organization_contract
}

data "terraform_remote_state" "aws_organization" {
  count   = local.read_organization ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

locals {
  # Org ARN for RAM org-wide sharing, built from existing organization outputs
  # (management account id + org id) so no extra remote-state dependency is
  # needed just to obtain the ARN.
  org_arn = "arn:${local.partition}:organizations::${local.org.management_account_id}:organization/${local.org.organization_id}"
}

module "aws_network_hub" {
  source = "../../../modules/aws/stages/network-hub"

  org_id  = local.org.organization_id
  org_arn = local.org_arn

  aws_region          = local.aws_region
  aws_enabled_regions = local.aws_enabled_regions

  top_cidr           = local.top_cidr
  regional_cidrs     = local.regional_cidrs
  inspection_cidr    = local.inspection_cidr
  egress_cidr        = local.egress_cidr
  availability_zones = var.availability_zones
  az_count           = var.az_count

  flow_log_destination_arn = "arn:${local.partition}:s3:::${local.log_archive_bucket_name}"
  log_bucket_name          = local.log_archive_bucket_name

  private_hosted_zone_name       = var.private_hosted_zone_name
  enable_network_firewall        = local.enable_network_firewall
  enable_network_access_analyzer = var.enable_network_access_analyzer

  enable_vpn = local.enable_vpn
  vpn        = local.vpn

  spoke_attachments = local.spoke_attachments

  enforce_egress_allowlist                  = local.enforce_egress_allowlist
  egress_alert_only_waived                  = local.egress_alert_only_waived
  network_firewall_egress_domain_allowlist  = local.network_firewall_egress_domain_allowlist
  network_firewall_stateful_default_actions = local.network_firewall_stateful_default_actions
}
