# MANDATORY (overridable set): deny a plan that weakens the HCP Terraform
# layer itself. envs/tfc-admin manages the policy sets that judge every
# workspace, each workspace's auto-apply settings and every team grant, so one
# reviewed apply could otherwise:
#   - detach a policy set (delete it, drop a workspace from workspace_ids,
#     turn off global, repoint its policy source or add an exclusion), which
#     removes the guard that judges the next run;
#   - turn on auto_apply / auto_apply_run_trigger on a control-plane,
#     bootstrap or production workspace (tags layer:control-plane,
#     layer:bootstrap, tier:production), or strip one of those tags, so a
#     change applies without a human confirmation;
#   - widen team access: a new grant, team member, organization member or
#     token, or a grant raised to a higher level;
#   - move a run off HCP-managed runners: a workspace switched to local or
#     agent execution, a repointed agent pool, or a new agent pool, agent
#     token or agent pool grant (an agent sees every credential of the run,
#     and a local run skips the policy sets);
#   - rewire a control-plane, bootstrap or production workspace: a changed
#     VCS repository, branch or connection (or a removed one, which lets the
#     CLI apply uploaded code), working directory or project;
#   - write an env var that steers credentials, the CLI or the runner
#     (TFC_*, TF_CLI_ARGS*, TFE_*, TF_TOKEN_*, and the code-execution names
#     tfc-admin refuses: TERRAFORM_CONFIG, TF_CLI_CONFIG_FILE, LD_*, DYLD_*,
#     NODE_OPTIONS, NODE_PATH, GIT_*, BASH_ENV, ENV, PYTHON*, PATH).
# Like destroy_guard, the set is overridable: the security team overrides an
# intended change (a new environment's grant, say) on the run.
package terraform.policies.tfc_admin_guard

import rego.v1

import data.terraform.lib

# ── Shared shapes ───────────────────────────────────────────────────────────
before_obj(rc) := rc.change.before if is_object(rc.change.before)

before_obj(rc) := {} if not is_object(rc.change.before)

after_obj(rc) := rc.change.after if is_object(rc.change.after)

after_obj(rc) := {} if not is_object(rc.change.after)

updates(rc) if "update" in rc.change.actions

# Set-or-list attribute as a set of strings (null or absent = empty).
str_set(obj, attr) := {v | some v in object.get(obj, attr, [])} if is_array(object.get(obj, attr, []))

str_set(obj, attr) := set() if not is_array(object.get(obj, attr, []))

# ── Policy sets: no detachment ──────────────────────────────────────────────
policy_attachment_types := {"tfe_policy_set", "tfe_workspace_policy_set", "tfe_project_policy_set"}

deny contains msg if {
	some rc in lib.managed
	rc.type in policy_attachment_types
	lib.deletes(rc)
	msg := sprintf("%s: plan deletes or replaces a policy set or its attachment, which leaves workspaces unjudged; the security team must override this run if it is intended", [rc.address])
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_policy_set"
	updates(rc)
	not lib.unknown(rc, "workspace_ids")
	removed := str_set(before_obj(rc), "workspace_ids") - str_set(after_obj(rc), "workspace_ids")
	count(removed) > 0
	msg := sprintf("%s: plan detaches the policy set from %d workspace(s) (%s); the security team must override this run if it is intended", [rc.address, count(removed), concat(", ", sort(removed))])
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_policy_set"
	updates(rc)
	object.get(before_obj(rc), "global", false) == true
	object.get(after_obj(rc), "global", null) == false
	msg := sprintf("%s: plan turns global off, which detaches the policy set from every workspace not listed; the security team must override this run if it is intended", [rc.address])
}

# Repointing the policy source (path, repository or branch) can empty the set.
policy_source(obj) := {
	"policies_path": object.get(obj, "policies_path", null),
	"vcs_repo": [{"identifier": object.get(v, "identifier", null), "branch": object.get(v, "branch", null)} | some v in object.get(obj, "vcs_repo", [])],
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_policy_set"
	updates(rc)
	not lib.unknown(rc, "policies_path")
	not lib.unknown(rc, "vcs_repo")
	policy_source(before_obj(rc)) != policy_source(after_obj(rc))
	msg := sprintf("%s: plan changes the policy set's source (policies_path or vcs_repo); the security team must override this run if it is intended", [rc.address])
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_policy_set"
	updates(rc)
	object.get(before_obj(rc), "overridable", null) == false
	object.get(after_obj(rc), "overridable", null) == true
	msg := sprintf("%s: plan makes a hard-gate policy set overridable; the security team must override this run if it is intended", [rc.address])
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_workspace_policy_set_exclusion"
	lib.creates(rc)
	msg := sprintf("%s: plan excludes a workspace from a policy set; the security team must override this run if it is intended", [rc.address])
}

# ── Auto-apply: never on control-plane or production workspaces ─────────────
protected_tags := {"layer:control-plane", "layer:bootstrap", "tier:production"}

workspace_tags(obj) := str_set(obj, "tag_names") | {k | some k, _ in object.get(obj, "tags", {})} if is_object(object.get(obj, "tags", {}))

workspace_tags(obj) := str_set(obj, "tag_names") if not is_object(object.get(obj, "tags", {}))

protected_workspace(rc) if {
	tags := workspace_tags(before_obj(rc)) | workspace_tags(after_obj(rc))
	some t in tags
	t in protected_tags
}

auto_apply_attrs := {"auto_apply", "auto_apply_run_trigger"}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_workspace"
	lib.writes(rc)
	protected_workspace(rc)
	some attr in auto_apply_attrs
	object.get(after_obj(rc), attr, false) == true
	object.get(before_obj(rc), attr, false) != true
	msg := sprintf("%s: plan enables %s on a control-plane, bootstrap or production workspace, so its runs would apply without a human confirmation; the security team must override this run if it is intended", [rc.address, attr])
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_workspace"
	updates(rc)
	not lib.unknown(rc, "tag_names")
	some t in (workspace_tags(before_obj(rc)) - workspace_tags(after_obj(rc)))
	t in protected_tags
	msg := sprintf("%s: plan removes the %s tag, which exempts the workspace from the auto-apply guard; the security team must override this run if it is intended", [rc.address, t])
}

# ── Team access: no widening ────────────────────────────────────────────────
# Any new grant, membership or token widens access.
grant_types := {
	"tfe_team_access",
	"tfe_team_project_access",
	"tfe_team_member",
	"tfe_team_members",
	"tfe_team_organization_member",
	"tfe_team_organization_members",
	"tfe_organization_membership",
	"tfe_team_token",
	"tfe_organization_token",
}

deny contains msg if {
	some rc in lib.managed
	rc.type in grant_types
	lib.creates(rc)
	msg := sprintf("%s: plan creates a %s, which widens team access; the security team must override this run if it is intended", [rc.address, rc.type])
}

# A team gaining organization-level access.
deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_team"
	lib.writes(rc)
	after_org := nested(after_obj(rc), "organization_access")
	before_org := nested(before_obj(rc), "organization_access")
	some f, v in after_org
	v == true
	object.get(before_org, f, false) != true
	msg := sprintf("%s: plan grants the team organization access %s; the security team must override this run if it is intended", [rc.address, f])
}

# Fixed access levels, least to most.
access_rank := {"read": 1, "plan": 2, "write": 3, "maintain": 4, "admin": 5}

# Per-permission levels; 0 is the least privilege.
field_rank := {
	"runs": {"read": 0, "plan": 1, "apply": 2},
	"variables": {"none": 0, "read": 1, "write": 2},
	"state_versions": {"none": 0, "read-outputs": 1, "read": 2, "write": 3},
	"sentinel_mocks": {"none": 0, "read": 1},
	"settings": {"read": 0, "update": 1, "delete": 2},
	"teams": {"none": 0, "read": 1, "manage": 2},
	"variable_sets": {"none": 0, "read": 1, "write": 2},
}

value_rank(_, v) := 1 if v == true

value_rank(_, v) := 0 if v == false

value_rank(f, v) := field_rank[f][v] if is_string(v)

# First element of a nested block (plan JSON renders blocks as lists).
nested(obj, block) := b if {
	blocks := object.get(obj, block, [])
	is_array(blocks)
	count(blocks) > 0
	b := blocks[0]
} else := {}

permission_blocks := {
	"tfe_team_access": ["permissions"],
	"tfe_team_project_access": ["project_access", "workspace_access"],
}

# The custom permissions of a grant, in the order of permission_blocks.
custom_perms(rc, obj) := object.union_n([nested(obj, b) | some b in permission_blocks[rc.type]])

# A custom grant's nearest fixed level (workspace create/delete/move or policy
# overrides count as admin; apply or variable/state write as write).
admin_flags := {"create", "delete", "move", "policy_overrides"}

custom_level(p) := 5 if {
	some f in admin_flags
	object.get(p, f, false) == true
} else := 3 if {
	write_like(p)
} else := 2 if {
	object.get(p, "runs", "") == "plan"
} else := 1

write_like(p) if object.get(p, "runs", "") == "apply"

write_like(p) if object.get(p, "variables", "") == "write"

write_like(p) if object.get(p, "state_versions", "") == "write"

grant_level(_, obj) := access_rank[obj.access] if obj.access != "custom"

grant_level(rc, obj) := custom_level(custom_perms(rc, obj)) if obj.access == "custom"

# A known value that is not the least privilege and not at most the old one.
field_widened(f, old, new) if {
	new != null
	new != old
	not least(f, new)
	not at_most(f, old, new)
}

least(f, v) if value_rank(f, v) == 0

least(_, v) if v == "none"

at_most(f, old, new) if value_rank(f, new) <= value_rank(f, old)

widened(rc) if {
	b := before_obj(rc)
	a := after_obj(rc)
	is_string(a.access)
	is_string(b.access)
	b.access != "custom"
	a.access != "custom"
	a.access != b.access
	not access_rank[a.access] <= access_rank[b.access]
}

widened(rc) if {
	b := before_obj(rc)
	a := after_obj(rc)
	is_string(a.access)
	is_string(b.access)
	a.access != b.access
	"custom" in {a.access, b.access}
	not grant_level(rc, a) <= grant_level(rc, b)
}

widened(rc) if {
	before_obj(rc).access == "custom"
	after_obj(rc).access == "custom"
	some block in permission_blocks[rc.type]
	old := nested(before_obj(rc), block)
	some f, new in nested(after_obj(rc), block)
	field_widened(f, object.get(old, f, null), new)
}

deny contains msg if {
	some rc in lib.managed
	rc.type in object.keys(permission_blocks)
	updates(rc)
	widened(rc)
	msg := sprintf("%s: plan raises a team's access level; the security team must override this run if it is intended", [rc.address])
}

# ── Execution mode and agent pools ──────────────────────────────────────────
# Any unknown value inside the attribute (nested blocks included).
attr_unknown(rc, attr) if {
	u := object.get(rc.change.after_unknown, attr, false)
	[_, v] := walk(u)
	v == true
}

# Modes that leave HCP-managed runners: an agent sees every credential of the
# run, and a local run is not judged by any policy set.
off_platform_modes := {"local", "agent"}

execution_types := {"tfe_workspace_settings", "tfe_workspace"}

deny contains msg if {
	some rc in lib.managed
	rc.type in execution_types
	lib.writes(rc)
	mode := object.get(after_obj(rc), "execution_mode", null)
	mode in off_platform_modes
	object.get(before_obj(rc), "execution_mode", null) != mode
	msg := sprintf("%s: plan sets execution_mode = %s, which moves runs off HCP-managed runners (an agent sees the run's credentials, a local run skips the policy sets); the security team must override this run if it is intended", [rc.address, mode])
}

deny contains msg if {
	some rc in lib.managed
	rc.type in execution_types
	lib.writes(rc)
	pool := object.get(after_obj(rc), "agent_pool_id", null)
	pool != null
	object.get(before_obj(rc), "agent_pool_id", null) != pool
	msg := sprintf("%s: plan points the workspace at agent pool %s; the security team must override this run if it is intended", [rc.address, pool])
}

# Unknown values. On tfe_workspace both attributes are deprecated and
# computed, so a create (or the create half of a replace) plans them unknown;
# only an update is judged there. agent_pool_id is Optional+Computed on
# tfe_workspace_settings too (tfe 0.83.0) and plans unknown on every create
# with agent_pool_id = null, so it is judged only when the mode is agent or
# itself unknown.
unknown_judged(rc) if rc.type == "tfe_workspace_settings"

unknown_judged(rc) if {
	rc.type == "tfe_workspace"
	not lib.creates(rc)
}

agent_or_unknown_mode(rc) if object.get(after_obj(rc), "execution_mode", null) == "agent"

agent_or_unknown_mode(rc) if attr_unknown(rc, "execution_mode")

unknown_execution_attr(rc, "execution_mode") if attr_unknown(rc, "execution_mode")

unknown_execution_attr(rc, "agent_pool_id") if {
	attr_unknown(rc, "agent_pool_id")
	agent_or_unknown_mode(rc)
}

deny contains msg if {
	some rc in lib.managed
	rc.type in execution_types
	lib.writes(rc)
	unknown_judged(rc)
	some attr in ["execution_mode", "agent_pool_id"]
	unknown_execution_attr(rc, attr)
	msg := sprintf("%s: %s is unknown at plan time, so the execution guard cannot check it; the security team must override this run if it is intended", [rc.address, attr])
}

agent_types := {
	"tfe_agent_pool",
	"tfe_agent_token",
	"tfe_agent_pool_allowed_workspaces",
	"tfe_agent_pool_allowed_projects",
	"tfe_agent_pool_excluded_workspaces",
}

deny contains msg if {
	some rc in lib.managed
	rc.type in agent_types
	lib.writes(rc)
	msg := sprintf("%s: plan creates or changes a %s, which lets runs execute on a self-hosted agent; the security team must override this run if it is intended", [rc.address, rc.type])
}

# ── Protected workspace wiring ──────────────────────────────────────────────
# Where a control-plane, bootstrap or production workspace takes its code
# from. A plain create is not judged (the new workspace has no reviewed wiring
# yet); an update or a replace (a write with a prior object) is.
vcs_source(obj) := [{
	"identifier": object.get(v, "identifier", null),
	"branch": object.get(v, "branch", null),
	"oauth_token_id": object.get(v, "oauth_token_id", null),
	"github_app_installation_id": object.get(v, "github_app_installation_id", null),
} |
	some v in object.get(obj, "vcs_repo", [])
]

wiring_attrs := {"vcs_repo", "working_directory", "project_id"}

rewrites(rc) if {
	lib.writes(rc)
	is_object(rc.change.before)
}

wiring(obj, "vcs_repo") := vcs_source(obj)

wiring(obj, attr) := object.get(obj, attr, null) if attr != "vcs_repo"

vcs_fields := {"identifier", "branch", "oauth_token_id", "github_app_installation_id"}

# Unknown only in the fields compared above (other vcs_repo fields, such as
# the computed repository_http_url, do not count).
wiring_unknown(rc, "vcs_repo") if {
	some v in object.get(rc.change.after_unknown, "vcs_repo", [])
	is_object(v)
	some f in vcs_fields
	object.get(v, f, false) == true
}

wiring_unknown(rc, "vcs_repo") if object.get(rc.change.after_unknown, "vcs_repo", false) == true

wiring_unknown(rc, attr) if {
	attr != "vcs_repo"
	attr_unknown(rc, attr)
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_workspace"
	rewrites(rc)
	protected_workspace(rc)
	some attr in wiring_attrs
	not wiring_unknown(rc, attr)
	wiring(before_obj(rc), attr) != wiring(after_obj(rc), attr)
	msg := sprintf("%s: plan changes %s on a control-plane, bootstrap or production workspace, which changes the code or the access its runs get; the security team must override this run if it is intended", [rc.address, attr])
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_workspace"
	rewrites(rc)
	protected_workspace(rc)
	some attr in wiring_attrs
	wiring_unknown(rc, attr)
	msg := sprintf("%s: %s is unknown at plan time on a control-plane, bootstrap or production workspace, so the wiring guard cannot check it; the security team must override this run if it is intended", [rc.address, attr])
}

# ── Env vars that steer credentials, the CLI or the runner ──────────────────
# Prefixes: dynamic credentials (TFC_*), CLI arguments (TF_CLI_ARGS*), the
# tfe provider and host tokens (TFE_*, TF_TOKEN_*). Exact names and patterns:
# the code-execution set envs/tfc-admin refuses (code_exec_env_pattern). Keep
# the two lists in step.
# scripts/check-env-pattern-sync.sh fails when the part after
# "TF_TOKEN_).*|" differs from code_exec_env_pattern in envs/tfc-admin.
steering_env_pattern := `^((TFC_|TF_CLI_ARGS|TFE_|TF_TOKEN_).*|TERRAFORM_CONFIG|TF_CLI_CONFIG_FILE|LD_[A-Z_]+|DYLD_[A-Z_]+|NODE_OPTIONS|NODE_PATH|GIT_[A-Z0-9_]+|BASH_ENV|BASH_FUNC_.+|ENV|SHELLOPTS|PS4|PYTHON[A-Z_]+|PERL5OPT|PERL5LIB|RUBYOPT|RUBYLIB|JAVA_TOOL_OPTIONS|_JAVA_OPTIONS|GCONV_PATH|SSH_ASKPASS[A-Z_]*|PATH)$`

steering_var(obj) if {
	object.get(obj, "category", null) == "env"
	regex.match(steering_env_pattern, object.get(obj, "key", ""))
}

var_payload(obj) := {f: object.get(obj, f, null) | some f in ["key", "category", "value", "value_wo_version"]}

var_changed(rc) if lib.creates(rc)

var_changed(rc) if {
	updates(rc)
	var_payload(before_obj(rc)) != var_payload(after_obj(rc))
}

var_changed(rc) if {
	updates(rc)
	some f in ["key", "category", "value", "value_wo_version"]
	attr_unknown(rc, f)
}

# A written variable whose key or category is unknown cannot be checked.
deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_variable"
	lib.writes(rc)
	some f in ["key", "category"]
	attr_unknown(rc, f)
	msg := sprintf("%s: the variable's %s is unknown at plan time, so the env var guard cannot check it; the security team must override this run if it is intended", [rc.address, f])
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_variable"
	var_changed(rc)
	steering_var(after_obj(rc))
	msg := sprintf("%s: plan writes the env var %s, which steers the run's credentials, the CLI or the runner; the security team must override this run if it is intended", [rc.address, after_obj(rc).key])
}

# ── Variable sets ───────────────────────────────────────────────────────────
# The tfe_variable rule above judges every variable this configuration writes
# into a set. A set managed elsewhere (made by hand in the UI) can hold any
# key, so attaching it to a workspace or project is denied; so is a global
# set, which reaches every workspace.
managed_set_ids contains id if {
	some rc in lib.managed
	rc.type == "tfe_variable_set"
	some obj in [before_obj(rc), after_obj(rc)]
	id := object.get(obj, "id", null)
	is_string(id)
}

creates_variable_set if {
	some rc in lib.managed
	rc.type == "tfe_variable_set"
	lib.creates(rc)
}

variable_set_attachment_types := {"tfe_workspace_variable_set", "tfe_project_variable_set"}

deny contains msg if {
	some rc in lib.managed
	rc.type in variable_set_attachment_types
	lib.writes(rc)
	set_id := object.get(after_obj(rc), "variable_set_id", null)
	is_string(set_id)
	not set_id in managed_set_ids
	msg := sprintf("%s: plan attaches variable set %s, which this configuration does not manage, so its env vars are not judged; the security team must override this run if it is intended", [rc.address, set_id])
}

# An ID still unknown must belong to a set this plan creates.
deny contains msg if {
	some rc in lib.managed
	rc.type in variable_set_attachment_types
	lib.writes(rc)
	attr_unknown(rc, "variable_set_id")
	not creates_variable_set
	msg := sprintf("%s: the attached variable set is unknown at plan time and no variable set is created in this plan; the security team must override this run if it is intended", [rc.address])
}

deny contains msg if {
	some rc in lib.managed
	rc.type == "tfe_variable_set"
	lib.writes(rc)
	object.get(after_obj(rc), "global", false) == true
	object.get(before_obj(rc), "global", false) != true
	msg := sprintf("%s: plan makes a variable set global, so its variables reach every workspace; the security team must override this run if it is intended", [rc.address])
}
