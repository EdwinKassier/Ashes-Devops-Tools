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
  }

  # Build attribute condition based on configuration:
  # 1. Use custom override if provided
  # 2. Otherwise, combine organization filter with ref restrictions
  attribute_condition = coalesce(
    var.github_attribute_condition_override,
    local.github_computed_condition
  )

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

locals {
  # Build the condition based on organization and allowed refs
  github_org_condition = var.github_organization != null ? "assertion.repository_owner == '${var.github_organization}'" : null

  # Build ref condition: supports multiple refs with OR logic
  github_ref_condition = length(var.github_allowed_refs) > 0 ? join(" || ", [
    for ref in var.github_allowed_refs : "assertion.ref == '${ref}'"
  ]) : null

  # Combine conditions with AND
  github_computed_condition = local.github_org_condition != null && local.github_ref_condition != null ? (
    "${local.github_org_condition} && (${local.github_ref_condition})"
  ) : coalesce(local.github_org_condition, local.github_ref_condition)
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

  attribute_condition = var.gitlab_namespace != null ? "assertion.namespace_path.startsWith('${var.gitlab_namespace}')" : null

  oidc {
    issuer_uri = var.gitlab_url
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
}

# Service Account IAM bindings for GitHub repos
resource "google_service_account_iam_member" "github_workload_identity" {
  for_each = { for binding in var.github_sa_bindings : "${binding.repository}-${binding.service_account_email}" => binding }

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository/${each.value.repository}"
}

# Service Account IAM bindings for GitLab projects
resource "google_service_account_iam_member" "gitlab_workload_identity" {
  for_each = { for binding in var.gitlab_sa_bindings : "${binding.project_path}-${binding.service_account_email}" => binding }

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.project_path/${each.value.project_path}"
}

# Terraform Cloud OIDC Provider (for Dynamic Credentials)
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
  }

  attribute_condition = var.tfc_organization != null ? "assertion.terraform_organization_name == '${var.tfc_organization}'" : null

  oidc {
    issuer_uri = "https://app.terraform.io"
  }
}

# Service Account IAM bindings for Terraform Cloud workspaces
resource "google_service_account_iam_member" "tfc_workload_identity" {
  for_each = { for binding in var.tfc_sa_bindings : "${binding.workspace_name}-${binding.service_account_email}" => binding }

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.terraform_workspace_name/${each.value.workspace_name}"
}
