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

  # RAM principals for the IPAM pools: null = the whole organization; otherwise
  # the ARNs of the OUs named by key in the organization contract's ou_ids.
  ipam_share_principal_arns = local.ipam_share_ou_keys == null ? null : [
    for k in local.ipam_share_ou_keys :
    "arn:${local.partition}:organizations::${local.org.management_account_id}:ou/${local.org.organization_id}/${lookup(local.org.ou_ids, k, "missing-${k}")}"
  ]
}

# Fails the plan when an OU key has no ID in the organization contract, instead
# of sharing the pools with a nonexistent OU.
resource "terraform_data" "ipam_share_ou_keys" {
  input = local.ipam_share_ou_keys

  lifecycle {
    precondition {
      condition     = local.ipam_share_ou_keys == null || alltrue([for k in coalesce(local.ipam_share_ou_keys, []) : contains(keys(local.org.ou_ids), k)])
      error_message = "ipam_share_ou_keys names OUs that are not in the organization contract's ou_ids: ${join(", ", [for k in coalesce(local.ipam_share_ou_keys, []) : k if !contains(keys(local.org.ou_ids), k)])}. Known OU keys: ${join(", ", sort(keys(local.org.ou_ids)))}."
    }
  }
}

module "aws_network_hub" {
  source = "../../../modules/aws/stages/network-hub"

  org_id  = local.org.organization_id
  org_arn = local.org_arn

  aws_region          = local.aws_region
  aws_enabled_regions = local.aws_enabled_regions

  top_cidr                  = local.top_cidr
  regional_cidrs            = local.regional_cidrs
  regional_additional_cidrs = local.regional_additional_cidrs
  share_principal_arns      = local.ipam_share_principal_arns
  inspection_cidr           = local.inspection_cidr
  egress_cidr               = local.egress_cidr
  availability_zones        = local.availability_zones # azs.tf
  az_count                  = var.az_count

  flow_log_destination_arn = "arn:${local.partition}:s3:::${local.log_archive_bucket_name}"
  log_bucket_name          = local.log_archive_bucket_name

  private_hosted_zone_name       = var.private_hosted_zone_name
  enable_network_firewall        = local.enable_network_firewall
  enable_network_access_analyzer = var.enable_network_access_analyzer

  enable_vpn                = local.enable_vpn
  vpn                       = local.vpn
  enable_resolver_endpoints = local.enable_resolver_endpoints

  spoke_attachments = local.spoke_attachments

  enforce_egress_allowlist                  = local.enforce_egress_allowlist
  egress_alert_only_waived                  = local.egress_alert_only_waived
  network_firewall_egress_domain_allowlist  = local.network_firewall_egress_domain_allowlist
  network_firewall_stateful_default_actions = local.network_firewall_stateful_default_actions
  network_firewall_suricata_rules           = local.network_firewall_suricata_rules
  network_firewall_internal_pass_cidrs      = local.network_firewall_internal_pass_cidrs

  vpc_endpoint_policy_mode = local.vpc_endpoint_policy_mode

  alarm_sns_topic_arn     = var.alarm_sns_topic_arn
  alarm_subscriber_emails = local.alarm_subscriber_emails
}

# A hub alarm that notifies nobody is worse than none (CMP-6): production needs
# a real subscriber or a topic the caller owns. Production = profile production,
# or any aws.workload_environments entry with is_production: true.
locals {
  alarm_placeholder_emails = sort([
    for e in local.alarm_subscriber_emails : e
    if can(regex("(^|\\.)(example\\.(com|net|org)|example|invalid|localhost|test)$", lower(try(regex("@([^@]+)$", e)[0], ""))))
  ])
  alarm_contact_required = local.profile == "production" || length(local.cfg.workload_production) > 0
}

resource "terraform_data" "alarm_contact_guard" {
  input = local.alarm_subscriber_emails

  lifecycle {
    precondition {
      condition = (
        !local.alarm_contact_required || var.alarm_sns_topic_arn != null ||
        (length(local.alarm_subscriber_emails) > 0 && length(local.alarm_placeholder_emails) == 0)
      )
      error_message = "Production hub network alarms have no real subscriber${length(local.alarm_placeholder_emails) > 0 ? " (placeholder domain: ${join(", ", local.alarm_placeholder_emails)})" : ""}. Set notifications.emails in config/landing-zone.yaml, alarm_subscriber_emails, or alarm_sns_topic_arn. Example, .invalid, .localhost and .test domains are rejected. Production means org.profile = production or an aws.workload_environments entry with is_production: true."
    }
  }
}

# The aws:ResourceOrgID endpoint policy is not yet sandbox-proven, so a
# regulated estate does not get it by default. Warn (never fail) until the
# owner opts in after a sandbox test (docs/known-gaps.md).
check "regulated_endpoint_policy" {
  assert {
    condition     = length(local.cfg.workload_regulated) == 0 || local.vpc_endpoint_policy_mode == "org_principals_and_resources"
    error_message = "Regulated AWS workload environments (${join(", ", local.cfg.workload_regulated)}) use hub interface endpoints that check only the caller (aws:PrincipalOrgID). Prove aws.network.vpc_endpoint_policy_mode: org_principals_and_resources in a sandbox, then set it (docs/architecture/regulated-environments.md)."
  }
}
