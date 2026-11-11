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
