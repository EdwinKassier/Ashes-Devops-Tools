# Google Cloud Workload Identity Federation Module
# Enables keyless authentication from external identity providers (GitHub Actions, AWS, Azure, etc.)

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "pool" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = var.display_name
  description               = var.description
  disabled                  = var.disabled
}

# GitHub Actions OIDC Provider
resource "google_iam_workload_identity_pool_provider" "github" {
  count = var.enable_github_provider ? 1 : 0
  # checkov:skip=CKV_GCP_125:The GitHub provider is constrained by repo-specific service account bindings and explicit subject/ref conditions, but Checkov does not fully resolve the composed module expression.

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions"
  description                        = "OIDC provider for GitHub Actions"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    # Immutable numeric IDs (C2): repository / owner NAMES can be renamed and then
    # re-registered by someone else, so bindings should key on these instead.
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
  }

  # Build attribute condition based on configuration:
  # 1. Use custom override if provided
  # 2. Otherwise, combine organization filter with ref restrictions
  attribute_condition = var.github_attribute_condition_override != null ? var.github_attribute_condition_override : local.github_computed_condition

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # H2: a null attribute_condition trusts the ENTIRE GitHub issuer (every repo on
  # token.actions.githubusercontent.com). When this provider is enabled it must be
  # scoped. Repository SA bindings are branch-agnostic, so scope the ref here too.
  lifecycle {
    precondition {
      condition     = var.github_attribute_condition_override != null || local.github_computed_condition != null
      error_message = "enable_github_provider requires a scoped attribute_condition: set github_attribute_condition_override, or github_organization and/or github_sa_bindings. A null condition would trust every GitHub repository."
    }
  }
}

locals {
  github_effective_refs = length(var.github_allowed_refs) > 0 ? var.github_allowed_refs : ["refs/heads/main"]
  github_subjects = distinct(flatten([
    for binding in var.github_sa_bindings : [
      for ref in local.github_effective_refs : "repo:${binding.repository}:ref:${ref}"
    ]
  ]))
  github_sub_condition = length(local.github_subjects) > 0 ? join(" || ", [
    for subject in local.github_subjects : "assertion.sub == '${subject}'"
  ]) : null
  github_org_condition = var.github_organization != null ? "assertion.repository_owner == '${var.github_organization}'" : null
  # Immutable owner pin (C2): survives an org rename / name squat.
  github_owner_id_condition = var.github_repository_owner_id != null ? "assertion.repository_owner_id == '${var.github_repository_owner_id}'" : null

  github_condition_parts = compact([
    local.github_sub_condition != null ? "(${local.github_sub_condition})" : "",
    local.github_org_condition != null ? local.github_org_condition : "",
    local.github_owner_id_condition != null ? local.github_owner_id_condition : "",
  ])
  github_computed_condition = length(local.github_condition_parts) > 0 ? join(" && ", local.github_condition_parts) : null
}

# GitLab CI OIDC Provider
resource "google_iam_workload_identity_pool_provider" "gitlab" {
  count = var.enable_gitlab_provider ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "gitlab"
  display_name                       = "GitLab CI"
  description                        = "OIDC provider for GitLab CI/CD"

  attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.project_id"     = "assertion.project_id"
    "attribute.project_path"   = "assertion.project_path"
    "attribute.namespace_path" = "assertion.namespace_path"
    "attribute.ref"            = "assertion.ref"
  }

  # Exact namespace or a sub-group of it. A bare startsWith('acme') would also
  # trust the unrelated groups 'acme-evil' and 'acmecorp' on the same issuer.
  attribute_condition = var.gitlab_namespace != null ? "assertion.namespace_path == '${trimsuffix(var.gitlab_namespace, "/")}' || assertion.namespace_path.startsWith('${trimsuffix(var.gitlab_namespace, "/")}/')" : null

  oidc {
    issuer_uri = var.gitlab_url
  }

  # H2: an enabled provider must be scoped, never a null (trust-all) condition.
  lifecycle {
    precondition {
      condition     = var.gitlab_namespace != null
      error_message = "enable_gitlab_provider requires gitlab_namespace; a null attribute_condition would trust the entire GitLab issuer."
    }
  }
}

# AWS OIDC Provider (for cross-cloud authentication)
resource "google_iam_workload_identity_pool_provider" "aws" {
  count = var.enable_aws_provider ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "aws-oidc"
  display_name                       = "AWS"
  description                        = "OIDC provider for AWS workloads"

  attribute_mapping = {
    "google.subject"    = "assertion.arn"
    "attribute.account" = "assertion.account"
    "attribute.role"    = "assertion.arn.extract('/assumed-role/{role}/')"
  }

  attribute_condition = var.aws_account_id != null ? "assertion.account == '${var.aws_account_id}'" : null

  aws {
    account_id = var.aws_account_id
  }

  # H2: an enabled provider must be scoped, never a null (trust-all) condition.
  lifecycle {
    precondition {
      condition     = var.aws_account_id != null
      error_message = "enable_aws_provider requires aws_account_id; a null attribute_condition would trust the entire AWS issuer."
    }
  }
}

# Service Account IAM bindings for GitHub repos
resource "google_service_account_iam_member" "github_workload_identity" {
  for_each = { for binding in var.github_sa_bindings : (binding.key != null ? binding.key : "${binding.repository}-${binding.service_account_email}") => binding }

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  # Prefer the immutable numeric repository_id when supplied (C2); the name-based
  # principalSet is kept only as a fallback for callers that have not set it.
  member = (
    each.value.repository_id != null
    ? "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository_id/${each.value.repository_id}"
    : "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository/${each.value.repository}"
  )
}

# Service Account IAM bindings for GitLab projects
resource "google_service_account_iam_member" "gitlab_workload_identity" {
  for_each = { for binding in var.gitlab_sa_bindings : "${binding.project_path}-${binding.service_account_email}" => binding }

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.project_path/${each.value.project_path}"
}

# Terraform Cloud OIDC Provider (for Dynamic Credentials)
#
# C2 hardening (Cloud Foundation Fabric FAST pattern):
#   * attribute_condition pins the TFC organization NAME and, when supplied, the
#     immutable organization ID and an allow-list of TFC project IDs, and only
#     admits the two real run phases.
#   * Two composite attributes join the workspace and the run phase so a single
#     principalSet can match BOTH (a principalSet can only test one attribute):
#       attribute.workspace_phase    = "<workspace_name>:<plan|apply>"
#       attribute.workspace_id_phase = "<workspace_id>:<plan|apply>"
#     Every SA binding below targets one of these, so a speculative/PR plan can
#     only ever obtain the read-only plan SA, never the apply SA.
locals {
  tfc_condition_parts = compact([
    var.tfc_organization != null ? "assertion.terraform_organization_name == '${var.tfc_organization}'" : "",
    var.tfc_organization_id != null ? "assertion.terraform_organization_id == '${var.tfc_organization_id}'" : "",
    length(var.tfc_project_ids) > 0 ? "assertion.terraform_project_id in [${join(", ", [for p in var.tfc_project_ids : "'${p}'"])}]" : "",
    "assertion.terraform_run_phase in ['plan', 'apply']",
  ])
  tfc_attribute_condition = var.tfc_organization != null ? join(" && ", local.tfc_condition_parts) : null

  tfc_principal_set_prefix = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}"
}

resource "google_iam_workload_identity_pool_provider" "tfc" {
  count = var.enable_tfc_provider ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "terraform-cloud"
  display_name                       = "Terraform Cloud"
  description                        = "OIDC provider for Terraform Cloud Dynamic Credentials"

  attribute_mapping = {
    "google.subject"                        = "assertion.sub"
    "attribute.aud"                         = "assertion.aud"
    "attribute.terraform_run_phase"         = "assertion.terraform_run_phase"
    "attribute.terraform_project_id"        = "assertion.terraform_project_id"
    "attribute.terraform_project_name"      = "assertion.terraform_project_name"
    "attribute.terraform_workspace_id"      = "assertion.terraform_workspace_id"
    "attribute.terraform_workspace_name"    = "assertion.terraform_workspace_name"
    "attribute.terraform_organization_id"   = "assertion.terraform_organization_id"
    "attribute.terraform_organization_name" = "assertion.terraform_organization_name"
    "attribute.terraform_run_id"            = "assertion.terraform_run_id"
    "attribute.terraform_full_workspace"    = "assertion.terraform_full_workspace"
    # Composite workspace+phase attributes (see header comment).
    "attribute.workspace_phase"    = "assertion.terraform_workspace_name + ':' + assertion.terraform_run_phase"
    "attribute.workspace_id_phase" = "assertion.terraform_workspace_id + ':' + assertion.terraform_run_phase"
  }

  attribute_condition = local.tfc_attribute_condition

  oidc {
    issuer_uri = "https://${var.tfc_hostname}"
  }

  # H2: an enabled provider must be scoped, never a null (trust-all) condition.
  lifecycle {
    precondition {
      condition     = var.tfc_organization != null
      error_message = "enable_tfc_provider requires tfc_organization; a null attribute_condition would trust the entire Terraform Cloud issuer."
    }
  }
}

# Service Account IAM bindings for Terraform Cloud workspaces, one per
# (workspace, run phase). Keyed statically on "<workspace_name>:<run_phase>" so
# the for_each keys never depend on apply-time SA emails. When workspace_id is
# supplied the binding matches the immutable workspace ID (a deleted-and-recreated
# or squatted workspace NAME then gains nothing); otherwise it falls back to the
# workspace name.
resource "google_service_account_iam_member" "tfc_workload_identity" {
  for_each = { for binding in var.tfc_sa_bindings : "${binding.workspace_name}:${binding.run_phase}" => binding }

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member = (
    each.value.workspace_id != null
    ? "${local.tfc_principal_set_prefix}/attribute.workspace_id_phase/${each.value.workspace_id}:${each.value.run_phase}"
    : "${local.tfc_principal_set_prefix}/attribute.workspace_phase/${each.value.workspace_name}:${each.value.run_phase}"
  )
}
