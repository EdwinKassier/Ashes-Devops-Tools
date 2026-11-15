# SaaS-only deployable root — Supabase and/or Vercel, nothing else.
#
# Cloud selection is which workspaces you apply, not a runtime flag. This root
# declares no aws/google provider, so applying saas-<name> pulls in no cloud
# credentials. Within the root, enable_supabase / enable_vercel gate the two
# SaaS features independently — either can be off and the root still validates
# because modules/saas/stages/saas-workload defaults the other's inputs.

module "saas_workload" {
  source = "../../modules/saas/stages/saas-workload"

  # ── Feature flags ─────────────────────────────────────────────────────────
  enable_supabase      = local.enable_supabase
  enable_vercel        = local.enable_vercel
  enable_vault_secrets = var.enable_vault_secrets

  # ── Supabase pass-through (used only when enable_supabase = true) ──────────
  supabase_organization_id      = local.supabase_organization_id
  supabase_project_name         = local.supabase_project_name
  supabase_database_password    = var.supabase_database_password
  supabase_region               = local.supabase_region
  supabase_disable_signup       = var.supabase_disable_signup
  supabase_mailer_autoconfirm   = var.supabase_mailer_autoconfirm
  supabase_password_min_length  = var.supabase_password_min_length
  supabase_api_max_rows         = var.supabase_api_max_rows
  supabase_db_schema            = var.supabase_db_schema
  supabase_db_extra_search_path = var.supabase_db_extra_search_path
  supabase_jwt_expiry           = var.supabase_jwt_expiry

  # ── Vault pass-through (used only when enable_vault_secrets = true) ─────────
  postgres_url      = var.postgres_url
  supabase_ssl_cert = var.supabase_ssl_cert
  vault_secrets     = var.vault_secrets

  # ── Vercel pass-through (used only when enable_vercel = true) ──────────────
  vercel_project_name      = local.vercel_project_name
  vercel_team_id           = local.vercel_team_id
  vercel_github_repo       = local.vercel_github_repo
  vercel_production_branch = local.vercel_production_branch
  vercel_root_directory    = var.vercel_root_directory
  vercel_framework         = var.vercel_framework
  vercel_serverless_region = var.vercel_serverless_region
  vercel_allowed_branches  = var.vercel_allowed_branches
  vercel_domains           = var.vercel_domains

  vercel_qa_env_vars   = var.vercel_qa_env_vars
  vercel_uat_env_vars  = var.vercel_uat_env_vars
  vercel_prod_env_vars = var.vercel_prod_env_vars
  # Caller-supplied shared env vars plus any resolved cross-cloud references.
  vercel_shared_env_vars = local.effective_vercel_shared_env_vars
}

# ── Cross-cloud wiring seam ──────────
#
# A SaaS root can consume an output from another cloud's root (AWS or GCP)
# WITHOUT configuring that cloud's provider: terraform_remote_state reads from
# state at plan time and needs only the TFC organization, no cloud credentials.
# This keeps `terraform validate -backend=false` credential-free (what CI runs).
#
# Opt-in via var.cross_cloud_references. Default empty: no upstream state is read
# and this root stays standalone. Each reference resolves an upstream output (for
# example a GCP/AWS runtime's API endpoint) into a shared Vercel env var, so the
# frontend learns the backend URL.

data "terraform_remote_state" "cross_cloud" {
  for_each = local.cross_cloud_workspaces

  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = each.value
    }
  }
}

locals {
  # Distinct upstream workspaces referenced (for_each key = workspace name).
  cross_cloud_workspaces = toset([for r in values(var.cross_cloud_references) : r.workspace_name])

  # Resolve each reference to a Vercel shared env var.
  cross_cloud_env_vars = [
    for k, r in var.cross_cloud_references : {
      key       = r.vercel_env_key
      value     = tostring(data.terraform_remote_state.cross_cloud[r.workspace_name].outputs[r.output_key])
      sensitive = r.sensitive
    }
  ]

  effective_vercel_shared_env_vars = concat(var.vercel_shared_env_vars, local.cross_cloud_env_vars)
}

# ── Data residency check (CMP-11) ─────────────────────────────────────────────
#
# saas.allowed_regions (else aws.allowed_regions) lists the AWS regions where
# this stack may process data. Both vendors run on AWS:
#   - Supabase region slugs are AWS region names
#     (https://supabase.com/docs/guides/platform/regions), so they are compared
#     as they are.
#   - Vercel function region codes map to one AWS region each, from the
#     "Region list" table at https://vercel.com/docs/regions. Keep this map, the
#     stage's vercel_serverless_region list and the vercel/project module's
#     serverless_function_region list in step.
# A code with no entry here becomes "unmapped:<code>", which is never in an
# allow list: when an allow list is set, an unmapped region fails the plan
# (fail closed). With no allow list there is no check, as before.
# Only the function region is checked. The Vercel CDN (points of presence,
# edge cache) is global and is not governed by this check.
locals {
  vercel_to_aws_region = {
    arn1 = "eu-north-1"
    bom1 = "ap-south-1"
    cdg1 = "eu-west-3"
    cle1 = "us-east-2"
    cpt1 = "af-south-1"
    dub1 = "eu-west-1"
    fra1 = "eu-central-1"
    gru1 = "sa-east-1"
    hkg1 = "ap-east-1"
    hnd1 = "ap-northeast-1"
    iad1 = "us-east-1"
    icn1 = "ap-northeast-2"
    kix1 = "ap-northeast-3"
    lhr1 = "eu-west-2"
    pdx1 = "us-west-2"
    sfo1 = "us-west-1"
    sin1 = "ap-southeast-1"
    syd1 = "ap-southeast-2"
    yul1 = "ca-central-1"
  }

  saas_allowed_regions = coalesce(local.cfg.saas_allowed_regions, local.cfg.aws_allowed_regions, [])
  saas_regions_in_use = compact([
    local.enable_supabase ? local.supabase_region : "",
    local.enable_vercel ? lookup(local.vercel_to_aws_region, var.vercel_serverless_region, "unmapped:${var.vercel_serverless_region}") : "",
  ])
  saas_regions_outside_allowed = length(local.saas_allowed_regions) == 0 ? [] : distinct([
    for r in local.saas_regions_in_use : r if !contains(local.saas_allowed_regions, r)
  ])
}

resource "terraform_data" "saas_residency_guard" {
  input = local.saas_regions_in_use

  lifecycle {
    precondition {
      condition     = length(local.saas_regions_outside_allowed) == 0
      error_message = "SaaS data would be processed outside the allowed regions (saas.allowed_regions, else aws.allowed_regions in config/landing-zone.yaml): ${join(", ", local.saas_regions_outside_allowed)}. Move supabase_region / vercel_serverless_region into the list, or add the region to saas.allowed_regions. An \"unmapped:<code>\" entry is a Vercel region this root cannot map to an AWS region; it fails closed."
    }
  }
}
