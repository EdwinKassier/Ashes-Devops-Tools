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
#
# The attribute_condition is ONLY the tenant pin, in its canonical form:
#   assertion.repository_owner_id == "<id>"
# The org-policy constraint custom.wifProviderTenantPinned compares the stored
# condition to that exact string, so nothing can be appended to it. Repository,
# ref and environment are pinned by the principalSet each SA is bound to, via
# the immutable composite attributes below.
resource "google_iam_workload_identity_pool_provider" "github" {
  count = var.enable_github_provider ? 1 : 0
  # checkov:skip=CKV_GCP_125:The condition pins the immutable repository_owner_id; repository and ref are pinned by the per-SA principalSet bindings (attribute.repository_id / attribute.repo_ref), which Checkov does not resolve.

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
    # Immutable numeric IDs: repository / owner NAMES can be renamed and then
    # re-registered by someone else, so bindings key on these instead.
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    # Composite attributes: a principalSet can test only ONE attribute, so the
    # repository is joined with the ref and/or environment. A token without
    # an environment claim maps to "-".
    "attribute.repo_ref"     = "assertion.repository_id + '/' + assertion.ref"
    "attribute.repo_env"     = "assertion.repository_id + '/' + (has(assertion.environment) ? assertion.environment : '-')"
    "attribute.repo_ref_env" = "assertion.repository_id + '/' + assertion.ref + '/' + (has(assertion.environment) ? assertion.environment : '-')"
  }

  attribute_condition = local.github_attribute_condition

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

locals {
  # Canonical tenant pin. github_repository_owner_id is required (and numeric)
  # whenever the provider is enabled; see variables.tf.
  github_attribute_condition = var.github_repository_owner_id == null ? null : "assertion.repository_owner_id == \"${var.github_repository_owner_id}\""

  github_principal_set_prefix = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}"

  # One binding per (SA binding, allowed ref). With github_allowed_refs the
  # member is attribute.repo_ref/<repository_id>/<ref>, so the branch pin the
  # condition used to carry survives. Without it the member stays on the
  # immutable repository_id (or, when the caller has not supplied one, the
  # repository name). A single allowed ref keeps the binding's own key, so a
  # caller with one ref keeps its state address.
  github_binding_refs = length(var.github_allowed_refs) > 0 ? var.github_allowed_refs : [null]
  github_bindings = merge([
    for b in var.github_sa_bindings : {
      for ref in local.github_binding_refs :
      (length(var.github_allowed_refs) > 1
        ? "${b.key != null ? b.key : "${b.repository}-${b.service_account_email}"}:${ref}"
        : (b.key != null ? b.key : "${b.repository}-${b.service_account_email}")
        ) => {
        service_account_email = b.service_account_email
        member = (
          ref != null
          ? "${local.github_principal_set_prefix}/attribute.repo_ref/${b.repository_id}/${ref}"
          : b.repository_id != null
          ? "${local.github_principal_set_prefix}/attribute.repository_id/${b.repository_id}"
          : "${local.github_principal_set_prefix}/attribute.repository/${b.repository}"
        )
      }
    }
  ]...)
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

  # An enabled provider must be scoped, never a null (trust-all) condition.
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

  # An enabled provider must be scoped, never a null (trust-all) condition.
  lifecycle {
    precondition {
      condition     = var.aws_account_id != null
      error_message = "enable_aws_provider requires aws_account_id; a null attribute_condition would trust the entire AWS issuer."
    }
  }
}

# Service Account IAM bindings for GitHub repos (see local.github_bindings).
resource "google_service_account_iam_member" "github_workload_identity" {
  for_each = local.github_bindings

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value.member
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

  # An enabled provider must be scoped, never a null (trust-all) condition.
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
