# tfc-admin: declare the whole Terraform Cloud workspace layer as code (audit C3).
#
# The workspaces, their working directories, VCS wiring and shared variables were
# previously created by hand in the TFC UI: unversioned, unreviewable, and
# invisible to the drift tooling. This root manages them from the same
# environments map the cloud roots consume, so a new environment or cloud is a
# reviewed change, not console clicking. Apply it FIRST (its own gcp-bootstrap-
# style chicken-and-egg: the tfc-admin workspace itself is created by hand once,
# then it manages all the others). It never applies cloud infrastructure.

locals {
  gcp_control_plane = {
    "gcp-bootstrap"    = { dir = "envs/gcp/bootstrap", desc = "GCP phase-0: admin project, Terraform admin SA, WIF pools", tags = ["cloud:gcp", "layer:bootstrap"] }
    "gcp-organization" = { dir = "envs/gcp/organization", desc = "GCP org: folders, org policy, KMS, audit, billing", tags = ["cloud:gcp", "layer:control-plane"] }
    "gcp-projects"     = { dir = "envs/gcp/projects", desc = "GCP host/spoke projects", tags = ["cloud:gcp", "layer:control-plane"] }
    "gcp-network-hub"  = { dir = "envs/gcp/network-hub", desc = "GCP hub VPC, DNS anchor, hub VPC-SC", tags = ["cloud:gcp", "layer:control-plane"] }
  }

  gcp_workloads = {
    for env in keys(var.environments) :
    "gcp-workload-${env}" => { dir = "envs/gcp/workload", desc = "GCP ${env} workload", tags = ["cloud:gcp", "layer:workload", "env:${env}"] }
  }

  aws_control_plane = var.enable_aws ? {
    "aws-organization"    = { dir = "envs/aws/organization", desc = "AWS org, SCP/RCP, account factory", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-security"        = { dir = "envs/aws/security", desc = "AWS security baseline + log archive", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-network"         = { dir = "envs/aws/network", desc = "AWS shared networking (TGW/IPAM)", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-identity"        = { dir = "envs/aws/identity", desc = "AWS IAM Identity Center", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-shared-services" = { dir = "envs/aws/shared-services", desc = "AWS shared platform services", tags = ["cloud:aws", "layer:control-plane"] }
    "aws-backup"          = { dir = "envs/aws/backup", desc = "AWS centralized backup", tags = ["cloud:aws", "layer:control-plane"] }
  } : {}

  aws_workloads = var.enable_aws ? {
    for env in keys(var.environments) :
    "aws-workload-${env}" => { dir = "envs/aws/workload", desc = "AWS ${env} workload", tags = ["cloud:aws", "layer:workload", "env:${env}"] }
  } : {}

  saas = {
    for name in var.saas_workspaces :
    "saas-${name}" => { dir = "envs/saas", desc = "SaaS ${name} (Supabase/Vercel)", tags = ["cloud:saas", "layer:workload"] }
  }

  workspaces = merge(
    local.gcp_control_plane,
    local.gcp_workloads,
    local.aws_control_plane,
    local.aws_workloads,
    local.saas,
  )
}

module "workspace" {
  source   = "../../modules/tfc/workspace"
  for_each = local.workspaces

  name              = each.key
  organization      = var.tfc_organization
  description       = each.value.desc
  working_directory = each.value.dir
  tag_names         = each.value.tags
  terraform_version = var.terraform_version

  # Trigger only on changes under the workspace's working directory.
  file_triggers_enabled = true

  vcs_repo = var.vcs_repo

  # Every workspace gets tfc_organization; operators add shared credential vars
  # (e.g. TFC_AWS_PROVIDER_AUTH) via common_workspace_variables.
  variables = merge(
    { tfc_organization = { value = var.tfc_organization, category = "terraform" } },
    var.common_workspace_variables,
  )

  # Control-plane and bootstrap workspaces alert on failed runs (audit M-ops);
  # workload workspaces use the separate workload channel (both default empty).
  notifications = (contains(each.value.tags, "layer:control-plane") || contains(each.value.tags, "layer:bootstrap")) ? var.control_plane_notifications : var.workload_notifications
}
