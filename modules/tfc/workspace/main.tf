# A single Terraform Cloud workspace plus its variables, settings, variable-set
# attachments and notifications, so the workspace layer (names, working
# directories, VCS wiring, triggers, remote-state sharing, health assessments,
# dynamic-credential env vars) is versioned and reviewable instead of
# hand-created in the UI (audit C3). Applied by the tfc-admin root.

resource "tfe_workspace" "this" {
  name         = var.name
  organization = var.organization
  description  = var.description
  project_id   = var.project_id

  working_directory = var.working_directory
  auto_apply        = var.auto_apply
  terraform_version = var.terraform_version
  tag_names         = var.tag_names

  # Native drift detection + continuous validation (health assessments).
  assessments_enabled = var.assessments_enabled

  # A control-plane workspace must not hand a privileged speculative plan to an
  # arbitrary PR (audit C2): speculative_enabled = false there.
  speculative_enabled = var.speculative_enabled
  allow_destroy_plan  = var.allow_destroy_plan

  queue_all_runs        = var.queue_all_runs
  file_triggers_enabled = var.file_triggers_enabled
  # trigger_patterns REPLACE the working-directory default, so callers must
  # include "<working_directory>/**" themselves (the tfc-admin root does).
  trigger_patterns = length(var.trigger_patterns) > 0 ? var.trigger_patterns : null

  dynamic "vcs_repo" {
    for_each = var.vcs_repo == null ? [] : [var.vcs_repo]
    content {
      identifier                 = vcs_repo.value.identifier
      branch                     = vcs_repo.value.branch
      oauth_token_id             = vcs_repo.value.oauth_token_id
      github_app_installation_id = vcs_repo.value.github_app_installation_id
    }
  }
}

# Execution mode and remote-state sharing live on tfe_workspace_settings (the
# tfe_workspace attributes are deprecated). global_remote_state defaults to false:
# state is shared ONLY with the explicit consumer workspaces that read it.
# A caller that wires consumers between sibling workspaces of the same for_each
# (the tfc-admin root) sets manage_settings = false and declares this resource
# itself, since a module instance cannot depend on its siblings' IDs.
resource "tfe_workspace_settings" "this" {
  count = var.manage_settings ? 1 : 0

  workspace_id              = tfe_workspace.this.id
  execution_mode            = var.execution_mode
  agent_pool_id             = var.execution_mode == "agent" ? var.agent_pool_id : null
  global_remote_state       = var.global_remote_state
  remote_state_consumer_ids = var.global_remote_state ? null : var.remote_state_consumer_ids
}

# Workspace variables (terraform inputs and env vars). Sensitive values are marked
# sensitive so they are write-only in TFC and never read back.
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

# Attach shared variable sets (org-wide values live once in a set, not copied
# onto every workspace). Keyed by a stable label so for_each is plan-known.
resource "tfe_workspace_variable_set" "this" {
  for_each = var.variable_set_ids

  workspace_id    = tfe_workspace.this.id
  variable_set_id = each.value
}

# Optional run notifications (audit M-ops): alert on failed or attention-needing
# runs for this workspace. Default empty, so this is opt-in per workspace.
resource "tfe_notification_configuration" "this" {
  for_each = var.notifications

  name             = each.key
  workspace_id     = tfe_workspace.this.id
  destination_type = each.value.destination_type
  enabled          = each.value.enabled
  triggers         = each.value.triggers

  url            = each.value.destination_type == "email" ? null : each.value.url
  token          = try(each.value.token, null)
  email_user_ids = each.value.destination_type == "email" ? each.value.email_user_ids : null
}
