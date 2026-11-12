package terraform.policies.tfc_admin_guard_test

import rego.v1

import data.terraform.policies.tfc_admin_guard as p

change(type, actions, before, after) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": actions, "before": before, "after": after, "after_unknown": {}},
}]}}

denied(inp) if count(p.deny) == 1 with input as inp

allowed(inp) if count(p.deny) == 0 with input as inp

# ── Policy sets ─────────────────────────────────────────────────────────────
policy_set(ids) := {"name": "opa", "global": false, "overridable": false, "policies_path": "policies/opa", "vcs_repo": [{"identifier": "acme/lz", "branch": "main"}], "workspace_ids": ids}

test_policy_set_delete_denied if denied(change("tfe_policy_set", ["delete"], policy_set(["ws-1"]), null))

test_policy_set_replace_denied if denied(change("tfe_policy_set", ["delete", "create"], policy_set(["ws-1"]), policy_set(["ws-1"])))

test_workspace_policy_set_delete_denied if denied(change("tfe_workspace_policy_set", ["delete"], {"policy_set_id": "polset-1", "workspace_id": "ws-1"}, null))

test_workspace_removed_from_policy_set_denied if denied(change("tfe_policy_set", ["update"], policy_set(["ws-1", "ws-2"]), policy_set(["ws-1"])))

test_workspace_added_to_policy_set_allowed if allowed(change("tfe_policy_set", ["update"], policy_set(["ws-1"]), policy_set(["ws-1", "ws-2"])))

test_policy_set_create_allowed if allowed(change("tfe_policy_set", ["create"], null, policy_set(["ws-1"])))

# A new workspace's ID is unknown at plan: the comparison is skipped.
test_unknown_workspace_ids_skipped if {
	inp := {"plan": {"resource_changes": [{
		"address": "tfe_policy_set.opa[0]",
		"mode": "managed",
		"type": "tfe_policy_set",
		"change": {
			"actions": ["update"],
			"before": policy_set(["ws-1", "ws-2"]),
			"after": object.remove(policy_set([]), ["workspace_ids"]),
			"after_unknown": {"workspace_ids": true},
		},
	}]}}
	allowed(inp)
}

test_global_turned_off_denied if denied(change("tfe_policy_set", ["update"], object.union(policy_set([]), {"global": true}), policy_set([])))

test_policies_path_repointed_denied if denied(change("tfe_policy_set", ["update"], policy_set(["ws-1"]), object.union(policy_set(["ws-1"]), {"policies_path": "policies/empty"})))

test_vcs_branch_repointed_denied if denied(change("tfe_policy_set", ["update"], policy_set(["ws-1"]), object.union(policy_set(["ws-1"]), {"vcs_repo": [{"identifier": "acme/lz", "branch": "attacker"}]})))

test_made_overridable_denied if denied(change("tfe_policy_set", ["update"], policy_set(["ws-1"]), object.union(policy_set(["ws-1"]), {"overridable": true})))

test_description_change_allowed if allowed(change("tfe_policy_set", ["update"], policy_set(["ws-1"]), object.union(policy_set(["ws-1"]), {"description": "new"})))

test_policy_set_exclusion_denied if denied(change("tfe_workspace_policy_set_exclusion", ["create"], null, {"policy_set_id": "polset-1", "workspace_id": "ws-1"}))

# ── Auto-apply ──────────────────────────────────────────────────────────────
ws(tags, auto) := {"name": "w", "tag_names": tags, "auto_apply": auto, "auto_apply_run_trigger": false}

test_auto_apply_on_control_plane_denied if denied(change("tfe_workspace", ["update"], ws(["layer:control-plane"], false), ws(["layer:control-plane"], true)))

test_auto_apply_on_production_denied if denied(change("tfe_workspace", ["update"], ws(["layer:workload", "tier:production"], false), ws(["layer:workload", "tier:production"], true)))

test_auto_apply_on_new_bootstrap_denied if denied(change("tfe_workspace", ["create"], null, ws(["layer:bootstrap"], true)))

test_auto_apply_run_trigger_on_production_denied if denied(change("tfe_workspace", ["update"], ws(["tier:production"], false), object.union(ws(["tier:production"], false), {"auto_apply_run_trigger": true})))

test_auto_apply_on_nonprod_workload_allowed if allowed(change("tfe_workspace", ["update"], ws(["layer:workload"], false), ws(["layer:workload"], true)))

test_auto_apply_already_on_allowed if allowed(change("tfe_workspace", ["update"], ws(["layer:control-plane"], true), object.union(ws(["layer:control-plane"], true), {"description": "x"})))

# Dropping the tag in the same plan does not hide the workspace.
test_auto_apply_with_tag_removed_denied if {
	inp := change("tfe_workspace", ["update"], ws(["tier:production"], false), ws([], true))
	count(p.deny) == 2 with input as inp
}

test_protected_tag_removed_denied if denied(change("tfe_workspace", ["update"], ws(["layer:workload", "tier:production"], false), ws(["layer:workload"], false)))

test_other_tag_removed_allowed if allowed(change("tfe_workspace", ["update"], ws(["layer:workload", "env:dev"], false), ws(["layer:workload"], false)))

# ── Team access ─────────────────────────────────────────────────────────────
test_new_team_access_denied if denied(change("tfe_team_access", ["create"], null, {"access": "write", "team_id": "team-1", "workspace_id": "ws-1"}))

test_new_project_access_denied if denied(change("tfe_team_project_access", ["create"], null, {"access": "read", "team_id": "team-1", "project_id": "prj-1"}))

test_new_team_member_denied if denied(change("tfe_team_organization_member", ["create"], null, {"team_id": "team-1"}))

test_new_team_token_denied if denied(change("tfe_team_token", ["create"], null, {"team_id": "team-1"}))

test_team_access_removed_allowed if allowed(change("tfe_team_access", ["delete"], {"access": "write", "team_id": "team-1"}, null))

test_fixed_level_raised_denied if denied(change("tfe_team_access", ["update"], {"access": "read"}, {"access": "write"}))

test_fixed_level_lowered_allowed if allowed(change("tfe_team_access", ["update"], {"access": "write"}, {"access": "read"}))

project_custom(runs, variables) := {
	"access": "custom",
	"project_access": [{"settings": "read", "teams": "none", "variable_sets": "read"}],
	"workspace_access": [{
		"runs": runs, "variables": variables, "state_versions": "read-outputs", "sentinel_mocks": "none",
		"locking": false, "create": false, "delete": false, "move": false, "run_tasks": false, "policy_overrides": false,
	}],
}

# Production workloads moving from fixed write to custom plan is a narrowing.
test_write_to_custom_plan_allowed if allowed(change("tfe_team_project_access", ["update"], {"access": "write"}, project_custom("plan", "read")))

test_read_to_custom_plan_denied if denied(change("tfe_team_project_access", ["update"], {"access": "read"}, project_custom("plan", "read")))

test_custom_to_write_denied if denied(change("tfe_team_project_access", ["update"], project_custom("plan", "read"), {"access": "write"}))

test_custom_runs_raised_denied if denied(change("tfe_team_project_access", ["update"], project_custom("plan", "read"), project_custom("apply", "read")))

test_custom_variables_raised_denied if denied(change("tfe_team_project_access", ["update"], project_custom("plan", "read"), project_custom("plan", "write")))

test_custom_runs_lowered_allowed if allowed(change("tfe_team_project_access", ["update"], project_custom("plan", "read"), project_custom("read", "read")))

test_custom_policy_overrides_granted_denied if {
	after := json.patch(project_custom("plan", "read"), [{"op": "replace", "path": "/workspace_access/0/policy_overrides", "value": true}])
	denied(change("tfe_team_project_access", ["update"], project_custom("plan", "read"), after))
}

test_custom_project_teams_raised_denied if {
	after := json.patch(project_custom("plan", "read"), [{"op": "replace", "path": "/project_access/0/teams", "value": "manage"}])
	denied(change("tfe_team_project_access", ["update"], project_custom("plan", "read"), after))
}

test_team_access_custom_state_raised_denied if denied(change(
	"tfe_team_access", ["update"],
	{"access": "custom", "permissions": [{"runs": "read", "variables": "none", "state_versions": "read-outputs"}]},
	{"access": "custom", "permissions": [{"runs": "read", "variables": "none", "state_versions": "read"}]},
))

test_unknown_access_skipped if allowed(change("tfe_team_access", ["update"], {"access": "read"}, {}))

test_team_org_access_granted_denied if denied(change(
	"tfe_team", ["update"],
	{"name": "t", "organization_access": [{"manage_policies": false, "manage_workspaces": false}]},
	{"name": "t", "organization_access": [{"manage_policies": true, "manage_workspaces": false}]},
))

test_team_without_org_access_allowed if allowed(change("tfe_team", ["create"], null, {"name": "t", "organization_access": [{"manage_policies": false}]}))

# ── Unrelated resources ─────────────────────────────────────────────────────
test_other_types_ignored if allowed(change("tfe_variable", ["delete"], {"key": "x"}, null))

# ── Execution mode and agent pools ──────────────────────────────────────────
settings(mode, pool) := {"workspace_id": "ws-1", "execution_mode": mode, "agent_pool_id": pool, "global_remote_state": false}

# Two messages: the agent mode and the pool.
test_execution_mode_to_agent_denied if {
	inp := change("tfe_workspace_settings", ["update"], settings("remote", null), settings("agent", "apool-1"))
	count(p.deny) == 2 with input as inp
}

test_execution_mode_to_local_denied if denied(change("tfe_workspace_settings", ["update"], settings("remote", null), settings("local", null)))

# gcp-bootstrap leaves local mode after pass 2 (bootstrap.md): toward remote passes.
test_execution_mode_local_to_remote_allowed if allowed(change("tfe_workspace_settings", ["update"], settings("local", null), settings("remote", null)))

# Two messages: the agent mode and the pool.
test_new_settings_in_agent_mode_denied if {
	inp := change("tfe_workspace_settings", ["create"], null, settings("agent", "apool-1"))
	count(p.deny) == 2 with input as inp
}

test_new_settings_in_remote_mode_allowed if allowed(change("tfe_workspace_settings", ["create"], null, settings("remote", null)))

test_agent_pool_repointed_denied if denied(change("tfe_workspace_settings", ["update"], settings("agent", "apool-1"), settings("agent", "apool-2")))

test_remote_state_change_allowed if allowed(change("tfe_workspace_settings", ["update"], settings("remote", null), object.union(settings("remote", null), {"global_remote_state": true})))

test_unknown_agent_pool_denied if {
	inp := {"plan": {"resource_changes": [{
		"address": "tfe_workspace_settings.x",
		"mode": "managed",
		"type": "tfe_workspace_settings",
		"change": {
			"actions": ["update"],
			"before": settings("agent", "apool-1"),
			"after": object.remove(settings("agent", null), ["agent_pool_id"]),
			"after_unknown": {"agent_pool_id": true},
		},
	}]}}
	denied(inp)
}

test_new_agent_pool_denied if denied(change("tfe_agent_pool", ["create"], null, {"name": "pool", "organization": "acme"}))

test_new_agent_token_denied if denied(change("tfe_agent_token", ["create"], null, {"agent_pool_id": "apool-1", "description": "t"}))

test_agent_pool_allowed_workspaces_widened_denied if denied(change("tfe_agent_pool_allowed_workspaces", ["update"], {"agent_pool_id": "apool-1", "allowed_workspace_ids": ["ws-1"]}, {"agent_pool_id": "apool-1", "allowed_workspace_ids": ["ws-1", "ws-2"]}))

# ── Protected workspace wiring: VCS, working directory, project ─────────────
pws(tags) := {
	"name": "gcp-organization", "tag_names": tags, "auto_apply": false, "auto_apply_run_trigger": false,
	"working_directory": "envs/gcp/organization", "project_id": "prj-gcp",
	"vcs_repo": [{"identifier": "acme/lz", "branch": "main", "oauth_token_id": null, "github_app_installation_id": "ghain-1"}],
}

test_protected_vcs_branch_changed_denied if denied(change("tfe_workspace", ["update"], pws(["layer:control-plane"]), object.union(pws(["layer:control-plane"]), {"vcs_repo": [{"identifier": "acme/lz", "branch": "attacker", "oauth_token_id": null, "github_app_installation_id": "ghain-1"}]})))

test_protected_vcs_identifier_changed_denied if denied(change("tfe_workspace", ["update"], pws(["tier:production"]), object.union(pws(["tier:production"]), {"vcs_repo": [{"identifier": "attacker/lz", "branch": "main", "oauth_token_id": null, "github_app_installation_id": "ghain-1"}]})))

test_protected_vcs_connection_changed_denied if denied(change("tfe_workspace", ["update"], pws(["layer:bootstrap"]), object.union(pws(["layer:bootstrap"]), {"vcs_repo": [{"identifier": "acme/lz", "branch": "main", "oauth_token_id": "ot-attacker", "github_app_installation_id": null}]})))

# Disconnecting VCS would let the CLI apply uploaded code.
test_protected_vcs_removed_denied if denied(change("tfe_workspace", ["update"], pws(["layer:control-plane"]), object.union(pws(["layer:control-plane"]), {"vcs_repo": []})))

test_protected_working_directory_changed_denied if denied(change("tfe_workspace", ["update"], pws(["layer:control-plane"]), object.union(pws(["layer:control-plane"]), {"working_directory": "envs/attacker"})))

test_protected_project_moved_denied if denied(change("tfe_workspace", ["update"], pws(["tier:production"]), object.union(pws(["tier:production"]), {"project_id": "prj-other"})))

test_protected_project_unknown_denied if {
	inp := {"plan": {"resource_changes": [{
		"address": "tfe_workspace.x",
		"mode": "managed",
		"type": "tfe_workspace",
		"change": {
			"actions": ["update"],
			"before": pws(["layer:control-plane"]),
			"after": object.remove(pws(["layer:control-plane"]), ["project_id"]),
			"after_unknown": {"project_id": true},
		},
	}]}}
	denied(inp)
}

test_unprotected_vcs_branch_changed_allowed if allowed(change("tfe_workspace", ["update"], pws(["layer:workload"]), object.union(pws(["layer:workload"]), {"vcs_repo": [{"identifier": "acme/lz", "branch": "dev", "oauth_token_id": null, "github_app_installation_id": "ghain-1"}]})))

test_unprotected_project_moved_allowed if allowed(change("tfe_workspace", ["update"], pws(["layer:workload"]), object.union(pws(["layer:workload"]), {"project_id": "prj-other"})))

test_new_protected_workspace_allowed if allowed(change("tfe_workspace", ["create"], null, pws(["layer:control-plane"])))

# A computed vcs_repo field that the guard does not compare does not count.
test_protected_vcs_computed_field_unknown_allowed if {
	inp := {"plan": {"resource_changes": [{
		"address": "tfe_workspace.x",
		"mode": "managed",
		"type": "tfe_workspace",
		"change": {
			"actions": ["update"],
			"before": pws(["layer:control-plane"]),
			"after": object.union(pws(["layer:control-plane"]), {"description": "x"}),
			"after_unknown": {"vcs_repo": [{"repository_http_url": true}]},
		},
	}]}}
	allowed(inp)
}

test_protected_vcs_branch_unknown_denied if {
	inp := {"plan": {"resource_changes": [{
		"address": "tfe_workspace.x",
		"mode": "managed",
		"type": "tfe_workspace",
		"change": {
			"actions": ["update"],
			"before": pws(["layer:control-plane"]),
			"after": pws(["layer:control-plane"]),
			"after_unknown": {"vcs_repo": [{"branch": true}]},
		},
	}]}}
	denied(inp)
}

# A new workspace's deprecated execution_mode / agent_pool_id are computed.
test_new_workspace_with_unknown_execution_mode_allowed if {
	inp := {"plan": {"resource_changes": [{
		"address": "tfe_workspace.x",
		"mode": "managed",
		"type": "tfe_workspace",
		"change": {
			"actions": ["create"],
			"before": null,
			"after": pws(["layer:control-plane"]),
			"after_unknown": {"execution_mode": true, "agent_pool_id": true, "id": true},
		},
	}]}}
	allowed(inp)
}

test_protected_trigger_patterns_changed_allowed if allowed(change("tfe_workspace", ["update"], pws(["layer:control-plane"]), object.union(pws(["layer:control-plane"]), {"trigger_patterns": ["envs/gcp/organization/**"]})))

# ── Variables that steer credentials, the CLI or the runner ─────────────────
var(key, category, value) := {"workspace_id": "ws-1", "key": key, "category": category, "value": value, "hcl": false, "sensitive": false, "value_wo_version": null}

test_new_tfc_env_var_denied if denied(change("tfe_variable", ["create"], null, var("TFC_AWS_APPLY_ROLE_ARN", "env", "arn:aws:iam::999999999999:role/x")))

test_tfc_env_var_value_changed_denied if denied(change("tfe_variable", ["update"], var("TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL", "env", "a@p.iam.gserviceaccount.com"), var("TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL", "env", "b@p.iam.gserviceaccount.com")))

test_tf_cli_args_env_var_denied if denied(change("tfe_variable", ["create"], null, var("TF_CLI_ARGS_plan", "env", "-var-file=x.tfvars")))

test_tfe_hostname_env_var_denied if denied(change("tfe_variable", ["create"], null, var("TFE_HOSTNAME", "env", "attacker.example")))

test_code_exec_env_var_denied if denied(change("tfe_variable", ["create"], null, var("LD_PRELOAD", "env", "/tmp/x.so")))

test_rotated_sensitive_tfc_var_denied if denied(change("tfe_variable", ["update"], object.union(var("TFC_X", "env", null), {"sensitive": true, "value_wo_version": 1}), object.union(var("TFC_X", "env", null), {"sensitive": true, "value_wo_version": 2})))

test_tfc_var_description_change_allowed if allowed(change("tfe_variable", ["update"], var("TFC_AWS_PROVIDER_AUTH", "env", "true"), object.union(var("TFC_AWS_PROVIDER_AUTH", "env", "true"), {"description": "new"})))

test_tfc_var_deleted_allowed if allowed(change("tfe_variable", ["delete"], var("TFC_AWS_PROVIDER_AUTH", "env", "true"), null))

test_ordinary_env_var_allowed if allowed(change("tfe_variable", ["create"], null, var("APP_NAME", "env", "x")))

test_terraform_input_named_tfc_allowed if allowed(change("tfe_variable", ["create"], null, var("TFC_note", "terraform", "x")))

test_provider_token_env_var_allowed if allowed(change("tfe_variable", ["create"], null, object.union(var("SUPABASE_ACCESS_TOKEN", "env", null), {"sensitive": true, "value_wo_version": 1})))
