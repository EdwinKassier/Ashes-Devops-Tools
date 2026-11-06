output "workspace_ids" {
  description = "Map of workspace name to its TFC workspace ID (ws-...)."
  value       = { for k, m in module.workspace : k => m.id }
}

output "workspace_names" {
  description = "The set of managed workspace names."
  value       = sort(keys(module.workspace))
}

output "project_ids" {
  description = "Map of project key (gcp, aws, saas, platform) to TFC project ID. Empty when enable_projects = false."
  value       = { for k, p in tfe_project.this : k => p.id }
}

output "common_variable_set_id" {
  description = "ID of the shared variable set attached to every managed workspace."
  value       = tfe_variable_set.common.id
}

output "remote_state_consumers" {
  description = "Remote-state sharing graph actually applied: producer workspace => consumer workspace names (tfc-admin added separately when *_outputs_from_tfc)."
  value       = { for k, v in local.consumer_names : k => sort(v) if length(v) > 0 }
}

output "dynamic_credential_workspaces" {
  description = "Workspaces that receive dynamic-credential env vars, by cloud."
  value = {
    gcp = sort(keys(local.gcp_credential_env))
    aws = sort(keys(local.aws_credential_env))
  }
}

output "policy_set_id" {
  description = "ID of the OPA policy set, or null when enable_policy_sets = false."
  value       = try(tfe_policy_set.opa[0].id, null)
}

output "workspace_execution_modes" {
  description = "Effective execution mode per managed workspace (execution_mode merged with workspace_execution_modes)."
  value       = local.execution_modes
}

output "workspace_variables_file_loaded" {
  description = "Whether the committed workspace_variables_file existed and was merged into the workspace variables."
  value       = local.workspace_variables_file_present
}

output "gcp_bootstrap_tfvars" {
  description = "tfvars line for the LOCAL phase-0 gcp-bootstrap apply (local execution mode ignores workspace variables): terraform -chdir=envs/tfc-admin output -raw gcp_bootstrap_tfvars > envs/gcp/bootstrap/tfc-workspaces.auto.tfvars"
  value       = "tfc_workspace_ids = ${jsonencode(local.gcp_bootstrap_workspace_ids)}\n"
}

output "run_triggers" {
  description = "Run-trigger edges created (\"<source>-><downstream>\")."
  value       = sort(keys(tfe_run_trigger.dag))
}

output "never_auto_apply_workspaces" {
  description = "Workspaces that always need a human apply confirmation, whatever any auto-apply setting does for the others (gcp-guardrails when GCP is enabled, and tfc-admin)."
  value       = sort([for ws in local.never_auto_apply_workspaces : ws if contains(keys(local.workspaces), ws) || ws == var.tfc_admin_workspace_name])
}

output "estate_config_trigger_patterns" {
  description = "Trigger patterns every workspace gets for this estate's own config: the landing-zone file + workspace_variables_file for production (config/landing-zone.yaml + config/tfc-workspaces.yaml by default), <dir>/** (plus an outside workspace_variables_file) for any other estate (e.g. config/sandbox/**)."
  value       = local.estate_config_trigger_patterns
}
