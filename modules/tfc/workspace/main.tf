# A single Terraform Cloud workspace plus its variables, so the workspace layer
# (names, working directories, VCS wiring, variables) is versioned and reviewable
# instead of hand-created in the UI (audit C3). This module is applied by the
# tfc-admin root, which runs in its own workspace.

resource "tfe_workspace" "this" {
  name         = var.name
  organization = var.organization
  description  = var.description

  working_directory = var.working_directory
  execution_mode    = var.execution_mode
  auto_apply        = var.auto_apply
  terraform_version = var.terraform_version
  tag_names         = var.tag_names

  # Speculative plans on PRs for this workspace's working directory.
  queue_all_runs        = var.queue_all_runs
  file_triggers_enabled = var.file_triggers_enabled
  trigger_patterns      = var.trigger_patterns

  dynamic "vcs_repo" {
    for_each = var.vcs_repo == null ? [] : [var.vcs_repo]
    content {
      identifier     = vcs_repo.value.identifier
      branch         = vcs_repo.value.branch
      oauth_token_id = vcs_repo.value.oauth_token_id
    }
  }
}

# Workspace variables (terraform inputs and env vars). Sensitive values are marked
# sensitive so they are write-only in TFC and never read back into state.
resource "tfe_variable" "this" {
  for_each = var.variables

  workspace_id = tfe_workspace.this.id
  key          = each.key
  value        = each.value.value
  category     = each.value.category
  hcl          = try(each.value.hcl, false)
  sensitive    = try(each.value.sensitive, false)
  description  = try(each.value.description, null)
}
