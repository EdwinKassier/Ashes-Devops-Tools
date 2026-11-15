package terraform.policies.tfc_vcs_run_only_test

import rego.v1

import data.terraform.policies.tfc_vcs_run_only as p

vcs := {"identifier": "acme/lz", "display_identifier": "acme/lz", "branch": "main", "ingress_submodules": false}

run(tags, repo, speculative, sha) := {"plan": {"resource_changes": []}, "run": {
	"id": "run-1",
	"speculative": speculative,
	"commit_sha": sha,
	"message": "Queued manually via the Terraform Enterprise API",
	"workspace": {"id": "ws-1", "name": "gcp-organization", "tags": tags, "vcs_repo": repo},
}}

denied(inp) if count(p.deny) == 1 with input as inp

allowed(inp) if count(p.deny) == 0 with input as inp

sha := "1e1c1018d1bbc0b8517d072718e0d87c1a0eda95"

# A run from the connected repository carries the commit SHA.
test_vcs_run_on_control_plane_allowed if allowed(run(["cloud:gcp", "layer:control-plane"], vcs, false, sha))

test_vcs_run_on_production_allowed if allowed(run(["layer:workload", "tier:production"], vcs, false, sha))

# An API-uploaded configuration version has no commit.
test_api_upload_on_control_plane_denied if denied(run(["cloud:gcp", "layer:control-plane"], vcs, false, ""))

test_api_upload_null_sha_on_production_denied if denied(run(["layer:workload", "tier:production"], vcs, false, null))

test_api_upload_on_bootstrap_denied if denied(run(["layer:bootstrap"], vcs, false, ""))

test_api_upload_missing_sha_denied if {
	inp := run(["layer:control-plane"], vcs, false, "")
	denied(json.remove(inp, ["run/commit_sha"]))
}

# A run without the speculative field is treated as one that can apply.
test_api_upload_missing_speculative_denied if {
	inp := run(["layer:control-plane"], vcs, false, "")
	denied(json.remove(inp, ["run/speculative"]))
}

# One message even when the workspace carries several protected tags.
test_api_upload_two_protected_tags_one_message if denied(run(["layer:control-plane", "tier:production"], vcs, false, ""))

test_api_upload_on_nonprod_workload_allowed if allowed(run(["layer:workload", "env:dev"], vcs, false, ""))

# A speculative plan cannot apply.
test_speculative_upload_on_control_plane_allowed if allowed(run(["layer:control-plane"], vcs, true, ""))

# A CLI-driven workspace (no VCS connection) is out of scope.
test_upload_on_cli_workspace_allowed if allowed(run(["layer:control-plane"], null, false, ""))

# A plan-only evaluation (opa eval, policy tests) carries no run data.
test_no_run_data_allowed if allowed({"plan": {"resource_changes": []}})
