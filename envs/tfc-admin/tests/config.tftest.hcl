# Single-source configuration: with tfc_organization / environments / enable_* /
# saas_workspaces / project_name_prefix / vcs_repo unset, tfc-admin derives the
# whole workspace layer from the landing-zone config file (a fixture here,
# config/landing-zone.yaml in a real estate). Explicit variables still win.

mock_provider "tfe" {}

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  workspace_variables_file = null
  # The fixture sets vcs_repo, so tfc-admin is self-managed (the default).
  # Mock providers cannot import; the import block runs in the adopting apply.
  import_tfc_admin_workspace = false
  # gcp-guardrails is security-team only; without a team a check warns.
  security_team_id = "team-security1"
  # Policy sets are off in most runs; the policy_sets_* runs turn the
  # unguarded-destroy warning back on and expect it.
  enable_unguarded_destroy_warning = false
  # The estate has a production environment and policy sets are off in most
  # runs: an unexpired waiver keeps the policy_sets_guard quiet. The
  # production_policy_sets_* runs unset it.
  policy_sets_waiver = { reason = "test estate without VCS policy sets", expires = "2099-12-31" }
}

run "workspaces_derived_from_config" {
  command = plan

  # 5 GCP control plane (incl. gcp-guardrails) + gcp-workload-{dev,prod} + 6 AWS
  # control plane + aws-workload-{dev,staging} + saas-{web,admin} + tfc-admin
  # (self-managed) = 18.
  assert {
    condition     = length(output.workspace_names) == 18
    error_message = "the workspace set must come from gcp/aws/saas .enabled, gcp.environments, aws.workload_environments and saas.workspaces."
  }

  # Each cloud uses its own environment list: no aws-workload-prod, no
  # gcp-workload-staging.
  assert {
    condition     = alltrue([for w in ["gcp-workload-dev", "gcp-workload-prod", "aws-workload-dev", "aws-workload-staging", "saas-web", "saas-admin"] : contains(output.workspace_names, w)]) && !contains(output.workspace_names, "aws-workload-prod") && !contains(output.workspace_names, "gcp-workload-staging")
    error_message = "gcp-workload-<env> must follow gcp.environments and aws-workload-<env> aws.workload_environments."
  }

  assert {
    condition     = local.tfc_organization == "cfg-tfc" && tfe_variable.common["tfc_organization"].value == "cfg-tfc" && tfe_project.this["gcp"].organization == "cfg-tfc"
    error_message = "tfc_organization must fall back to org.tfc.organization."
  }
}

# Speculative plans follow is_production from gcp.environments /
# aws.workload_environments (aws staging is flagged production in the fixture).
run "production_from_config" {
  command = plan

  assert {
    condition     = module.workspace["gcp-workload-prod"].speculative_enabled == false && module.workspace["aws-workload-staging"].speculative_enabled == false
    error_message = "workloads whose environment is_production must not run speculative plans."
  }

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == true && module.workspace["aws-workload-dev"].speculative_enabled == true
    error_message = "non-production workloads keep speculative plans."
  }
}

run "workload_account_key_from_config" {
  command = plan

  assert {
    condition     = module.workspace["aws-workload-staging"].variable_values["workload_account_key"] == "workload_staging" && module.workspace["aws-workload-staging"].variable_values["environment"] == "staging"
    error_message = "aws-workload-<env> must get workload_account_key from aws.workload_environments[<env>].account_key."
  }
}

# Project names: <project_name_prefix><cloud>, with an explicit
# org.tfc.aws_project winning (the same key aws-organization's tfc_project reads).
run "project_names_from_config" {
  command = plan

  assert {
    condition     = tfe_project.this["gcp"].name == "lz-gcp" && tfe_project.this["saas"].name == "lz-saas" && tfe_project.this["aws"].name == "aws-landing-zone"
    error_message = "project names must come from org.tfc.project_name_prefix / org.tfc.<cloud>_project."
  }

  assert {
    condition     = tfe_variable_set.common.name == "lz-common"
    error_message = "the variable-set name must use the config project_name_prefix."
  }
}

run "vcs_repo_and_pinned_opa_from_config" {
  command = plan

  variables {
    enable_policy_sets = true
  }

  assert {
    condition     = tfe_policy_set.opa[0].vcs_repo[0].identifier == "cfg/landing-zone" && tfe_policy_set.opa[0].vcs_repo[0].branch == "main" && can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.opa_version)) && tfe_policy_set.opa[0].policy_tool_version == var.opa_version
    error_message = "vcs_repo must fall back to org.tfc.vcs_repo (branch default main) and opa_version must be pinned by default."
  }
}

run "explicit_variables_win_over_config" {
  command = plan

  variables {
    tfc_organization    = "acme"
    enable_aws          = false
    enable_saas         = false
    project_name_prefix = "x-"
    environments        = { qa = { is_production = false } }
    enable_policy_sets  = true
    vcs_repo            = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
  }

  assert {
    condition     = tfe_policy_set.opa[0].vcs_repo[0].identifier == "acme/landing-zone"
    error_message = "an explicit vcs_repo must override org.tfc.vcs_repo."
  }

  assert {
    condition     = toset(output.workspace_names) == toset(["gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub", "gcp-guardrails", "gcp-workload-qa", "tfc-admin"]) && local.tfc_organization == "acme"
    error_message = "explicit enable_* / environments / tfc_organization must override the config file."
  }

  # The config's explicit org.tfc.gcp_project is unset, so the variable prefix applies.
  assert {
    condition     = tfe_project.this["gcp"].name == "x-gcp"
    error_message = "an explicit project_name_prefix must override org.tfc.project_name_prefix."
  }
}

run "missing_organization_fails" {
  command = plan

  variables {
    landing_zone_config_path = ""
    enable_gcp               = true
  }

  expect_failures = [var.tfc_organization]
}

run "untouched_placeholder_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-placeholder.yaml"
  }

  expect_failures = [var.tfc_organization]
}

run "shipped_example_is_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "../../config/landing-zone.example.yaml"
  }

  # Placeholder TFC org, and every cloud disabled until the adopter opts in.
  expect_failures = [var.tfc_organization, var.enable_gcp]
}

# enable_policy_sets = null: the fixture sets org.tfc.vcs_repo and
# org.tfc.plan = standard, so both policy sets turn on by themselves.
run "policy_sets_on_with_vcs_and_paid_plan" {
  command = plan

  assert {
    condition     = length(tfe_policy_set.opa) == 1 && length(tfe_policy_set.destructive) == 1
    error_message = "a vcs_repo plus a plan with VCS policy sets must turn both policy sets on."
  }

  assert {
    condition     = tfe_policy_set.destructive[0].overridable == true && tfe_policy_set.opa[0].overridable == false
    error_message = "only the destructive-change guard is overridable."
  }
}

run "policy_sets_off_on_free_plan" {
  command = plan

  variables {
    tfc_plan                         = "free"
    enable_unguarded_destroy_warning = true
  }

  assert {
    condition     = length(tfe_policy_set.opa) == 0 && length(tfe_policy_set.destructive) == 0
    error_message = "the free plan does not get the policy sets by default."
  }

  expect_failures = [check.destructive_changes_guarded]
}

run "explicit_enable_policy_sets_false_wins" {
  command = plan

  variables {
    enable_policy_sets               = false
    enable_unguarded_destroy_warning = true
  }

  assert {
    condition     = length(tfe_policy_set.opa) == 0 && length(tfe_policy_set.destructive) == 0
    error_message = "an explicit enable_policy_sets = false must override the derived default."
  }

  expect_failures = [check.destructive_changes_guarded]
}

# notifications.hcp_email_user_ids becomes an email notification (user IDs, not
# addresses) on failed runs and every health-assessment event.
run "hcp_assessment_notifications_use_user_ids" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
  }

  assert {
    condition = (
      local.control_plane_notifications["notify-email"].destination_type == "email" &&
      toset(local.control_plane_notifications["notify-email"].email_user_ids) == toset(["user-aaa", "user-bbb"]) &&
      contains(local.control_plane_notifications["notify-email"].triggers, "assessment:drifted") &&
      contains(local.control_plane_notifications["notify-email"].triggers, "assessment:check_failure") &&
      contains(local.control_plane_notifications["notify-email"].triggers, "assessment:failed") &&
      contains(local.control_plane_notifications["notify-email"].triggers, "run:errored")
    )
    error_message = "hcp_email_user_ids must produce an email notification with run:errored and the three assessment triggers."
  }

  assert {
    condition     = contains(keys(local.workload_notifications), "notify-email")
    error_message = "workload workspaces must receive the assessment email notification too."
  }
}

# Explicitly configured notifications are kept; the section only adds its entry.
run "explicit_notifications_are_kept" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
    control_plane_notifications = {
      ops = { destination_type = "generic", url = "https://hooks.example.com/x" }
    }
  }

  assert {
    condition     = contains(keys(local.control_plane_notifications), "ops") && contains(keys(local.control_plane_notifications), "notify-email")
    error_message = "an explicit notification must be kept alongside the config-derived email entry."
  }
}

run "no_section_is_noop" {
  command = plan

  assert {
    condition     = length(local.control_plane_notifications) == 0 && length(local.workload_notifications) == 0
    error_message = "without a notifications section no notification is created."
  }
}

run "placeholder_hcp_user_id_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications-placeholder.yaml"
  }

  expect_failures = [var.control_plane_notifications]
}

# Scaffold matrix: committed scaffolder output (make scaffold-fixtures) must plan.
run "scaffold_gcp_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../tests/fixtures/scaffold/landing-zone.gcp.yaml"
    policy_sets_waiver       = null
  }

  # ADO-20: the production scaffold writes org.tfc.plan (standard) and
  # vcs_repo, so the policy sets are on and the estate needs no waiver.
  assert {
    condition     = local.tfc_plan == "standard" && local.enable_policy_sets
    error_message = "the production scaffold must turn the OPA policy sets on (org.tfc.plan standard + vcs_repo)."
  }
}

run "scaffold_aws_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../tests/fixtures/scaffold/landing-zone.aws.yaml"
    policy_sets_waiver       = null
  }

  # ADO-20: the production scaffold writes org.tfc.plan (standard) and
  # vcs_repo, so the policy sets are on and the estate needs no waiver.
  assert {
    condition     = local.tfc_plan == "standard" && local.enable_policy_sets
    error_message = "the production scaffold must turn the OPA policy sets on (org.tfc.plan standard + vcs_repo)."
  }
}

run "scaffold_saas_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../tests/fixtures/scaffold/landing-zone.saas.yaml"
    policy_sets_waiver       = null
  }

  # ADO-20: the production scaffold writes org.tfc.plan (standard) and
  # vcs_repo, so the policy sets are on and the estate needs no waiver.
  assert {
    condition     = local.tfc_plan == "standard" && local.enable_policy_sets
    error_message = "the production scaffold must turn the OPA policy sets on (org.tfc.plan standard + vcs_repo)."
  }
}

run "scaffold_gcp_aws_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../tests/fixtures/scaffold/landing-zone.gcp-aws.yaml"
    policy_sets_waiver       = null
  }

  # ADO-20: the production scaffold writes org.tfc.plan (standard) and
  # vcs_repo, so the policy sets are on and the estate needs no waiver.
  assert {
    condition     = local.tfc_plan == "standard" && local.enable_policy_sets
    error_message = "the production scaffold must turn the OPA policy sets on (org.tfc.plan standard + vcs_repo)."
  }
}

run "scaffold_gcp_aws_saas_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../tests/fixtures/scaffold/landing-zone.gcp-aws-saas.yaml"
    policy_sets_waiver       = null
  }

  # ADO-20: the production scaffold writes org.tfc.plan (standard) and
  # vcs_repo, so the policy sets are on and the estate needs no waiver.
  assert {
    condition     = local.tfc_plan == "standard" && local.enable_policy_sets
    error_message = "the production scaffold must turn the OPA policy sets on (org.tfc.plan standard + vcs_repo)."
  }
}

# Address plan: the committed fixture follows docs/architecture/cidr-plan.md
# (GCP 10.0.0.0/12, AWS defaults in 10.64.0.0/10), so no conflict is reported.
run "cidr_plan_clean_config_has_no_conflict" {
  command = plan

  assert {
    condition     = length(local.cidr_overlaps) == 0 && length(local.cidr_outside_aws_top) == 0
    error_message = "the plan-conformant fixture must report no address conflict."
  }

  assert {
    condition     = local.cidr_aws_top == "10.64.0.0/10" && local.cidr_all["aws.network.inspection_cidr"] == "10.64.0.0/16" && local.cidr_all["gcp.environments.prod.cidr_block"] == "10.30.0.0/16"
    error_message = "the check must see the GCP ranges and the aws-network defaults."
  }
}

# The old aws-network defaults sat on the GCP hub: tfc-admin fails the plan and
# names each conflicting pair.
run "cidr_overlap_fails_the_plan" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-overlap.yaml"
  }

  assert {
    condition = (
      contains(local.cidr_overlaps, "aws.network.inspection_cidr (10.0.0.0/16) overlaps gcp.network.hub_cidr_block (10.0.0.0/16)") &&
      contains(local.cidr_overlaps, "aws.network.top_cidr (10.0.0.0/8) overlaps gcp.environments.dev.cidr_block (10.10.0.0/16)") &&
      !anytrue([for o in local.cidr_overlaps : startswith(o, "aws.network.top_cidr") && strcontains(o, "overlaps aws.")])
    )
    error_message = "overlaps across clouds are reported pairwise; AWS VPCs inside the AWS supernet are not."
  }

  assert {
    condition     = length(local.cidr_outside_aws_top) == 0
    error_message = "every fixed AWS range sits inside top_cidr 10.0.0.0/8 here."
  }

  expect_failures = [terraform_data.input_contract]
}

run "cidr_outside_aws_supernet_fails_the_plan" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-outside.yaml"
  }

  assert {
    condition     = length(local.cidr_outside_aws_top) == 1 && contains(local.cidr_outside_aws_top, "aws.workload_environments.dev.vpc_cidr (10.20.0.0/16) is outside aws.network.top_cidr (10.64.0.0/10)")
    error_message = "a fixed workload vpc_cidr outside top_cidr is reported."
  }

  expect_failures = [terraform_data.input_contract]
}

# Production is the is_production flag alone: a config environment (either
# cloud) without it fails the plan, naming the entry.
run "config_environment_without_is_production_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-missing-is-production.yaml"
  }

  expect_failures = [var.environments]
}

# Re-audit 5 CMP-3: an explicit environments map cannot mark a regulated
# environment non-production.
run "environments_override_cannot_unmark_regulated" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    environments = {
      dev = { is_production = false, aws_account_key = "workload_dev" }
      pci = { is_production = false, aws_account_key = "workload_pci" }
    }
  }

  expect_failures = [var.environments]
}

run "regulated_config_plans" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
  }

  assert {
    condition     = local.cfg.regulated_keys == tolist(["pci"])
    error_message = "the regulated keys of both clouds must be read from the config file."
  }
}

# CMP-1: a regulated environment (either cloud) must be is_production: true.
run "regulated_environment_not_production_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated-not-production.yaml"
  }

  expect_failures = [var.environments]
}

run "workloads_sharing_the_default_vpc_cidr_fail_the_plan" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-pool.yaml"
  }

  assert {
    condition     = contains(local.cidr_overlaps, "aws.workload_environments.dev.vpc_cidr (10.72.0.0/16) overlaps aws.workload_environments.staging.vpc_cidr (10.72.0.0/16)")
    error_message = "A workload without vpc_cidr takes the built-in 10.72.0.0/16; two of them must be reported as an overlap."
  }

  assert {
    condition     = contains(local.cidr_outside_aws_pool, "aws.workload_environments.perf.vpc_cidr (10.96.0.0/16) is outside the eu-west-2 regional pool (10.64.0.0/12)")
    error_message = "A fixed AWS VPC range outside the home-region pool must be reported."
  }

  expect_failures = [terraform_data.input_contract]
}

# A static hub CIDR outside the regional pool cannot conflict with IPAM, so it
# passes while it overlaps nothing.
run "hub_cidr_outside_the_pool_passes" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-hub-outside-pool.yaml"
  }

  assert {
    condition     = local.cidr_all["aws.network.inspection_cidr"] == "10.100.0.0/16" && length(local.cidr_overlaps) == 0 && length(local.cidr_outside_aws_top) == 0 && length(local.cidr_outside_aws_pool) == 0
    error_message = "A hub inspection_cidr outside the pool (inside top_cidr) must be accepted."
  }
}

# A hub CIDR outside the pool still fails when it overlaps a workload range.
run "hub_cidr_outside_the_pool_overlapping_a_workload_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-hub-overlap.yaml"
  }

  assert {
    condition     = contains(local.cidr_overlaps, "aws.network.egress_cidr (10.96.0.0/16) overlaps aws.workload_environments.dev.vpc_cidr (10.96.0.0/16)")
    error_message = "A hub CIDR outside the pool must still be checked against every workload range."
  }

  assert {
    condition     = !anytrue([for o in local.cidr_outside_aws_pool : strcontains(o, "aws.network.")])
    error_message = "Hub CIDRs are not part of the regional pool check."
  }

  expect_failures = [terraform_data.input_contract]
}

# A workload may take its range from any CIDR of the home-region pool, the first
# one or an additional one (aws.network.regional_additional_cidrs). perf at
# 10.96.0.0/16 sits in neither, so it is still reported.
run "workload_inside_an_additional_pool_cidr_passes" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-additional-pool.yaml"
  }

  assert {
    condition     = length(local.cidr_overlaps) == 0 && length(local.cidr_outside_aws_top) == 0 && length(local.cidr_pool_issues) == 0
    error_message = "A second pool CIDR inside top_cidr and clear of the first must pass."
  }

  assert {
    condition     = length(local.cidr_outside_aws_pool) == 1 && contains(local.cidr_outside_aws_pool, "aws.workload_environments.perf.vpc_cidr (10.96.0.0/16) is outside the eu-west-2 regional pool (10.64.0.0/12, 10.80.0.0/12)")
    error_message = "Only the workload outside every home-region pool CIDR is reported; 10.81.0.0/16 (inside the additional CIDR) is not."
  }

  expect_failures = [terraform_data.input_contract]
}

# Additional pool CIDRs must sit inside top_cidr and overlap no other pool CIDR.
run "additional_pool_cidrs_outside_top_or_overlapping_fail" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-additional-bad.yaml"
  }

  assert {
    condition = (
      contains(local.cidr_pool_issues, "aws.network.regional_additional_cidrs.eu-west-2[0] (10.20.0.0/12) is outside aws.network.top_cidr (10.64.0.0/10)") &&
      contains(local.cidr_pool_issues, "aws.network.regional_additional_cidrs.eu-west-2[1] (10.64.0.0/13) overlaps aws.network.regional_cidrs.eu-west-2 (10.64.0.0/12)") &&
      length(local.cidr_pool_issues) == 2
    )
    error_message = "An additional pool CIDR outside top_cidr, or overlapping another pool CIDR, must be reported (and a clean one must not)."
  }

  expect_failures = [terraform_data.input_contract]
}

# With the AWS VPN on, each on-premises prefix is checked against the AWS and
# GCP ranges. Prefixes on the on-premises side may overlap each other.
run "onprem_prefix_overlapping_aws_ranges_fails_the_plan" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-onprem-overlap.yaml"
  }

  assert {
    condition = (
      contains(local.cidr_overlaps, "aws.network.inspection_cidr (10.64.0.0/16) overlaps aws.network.vpn.onprem_cidrs[0] (10.64.5.0/24)") &&
      contains(local.cidr_overlaps, "aws.network.top_cidr (10.64.0.0/10) overlaps aws.network.vpn.onprem_cidrs[0] (10.64.5.0/24)") &&
      contains(local.cidr_overlaps, "aws.network.vpn.onprem_cidrs[1] (10.72.0.0/12) overlaps aws.workload_environments.dev.vpc_cidr (10.72.0.0/16)") &&
      !anytrue([for o in local.cidr_overlaps : strcontains(o, "192.168.")])
    )
    error_message = "On-premises prefixes that overlap AWS ranges (top_cidr included) must be reported; on-premises prefixes overlapping each other must not."
  }

  expect_failures = [terraform_data.input_contract]
}

run "onprem_prefixes_clear_of_aws_ranges_pass" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-onprem-clean.yaml"
  }

  assert {
    condition     = local.cidr_all["aws.network.vpn.onprem_cidrs[2]"] == "172.16.0.0/12" && length(local.cidr_overlaps) == 0 && length(local.cidr_outside_aws_top) == 0 && length(local.cidr_outside_aws_pool) == 0
    error_message = "On-premises prefixes clear of every AWS and GCP range must pass, and they are not held to top_cidr or the pool."
  }
}

# ── aws.layers: the minimum AWS footprint ──────────────────────────────────
# aws.layers: [] keeps aws-organization and aws-security (always created) and
# the aws-workload-<env> family; the four optional layers, and every grant,
# trigger and consumer edge that names them, drop out.
run "aws_layers_empty_creates_only_organization_and_security" {
  command = plan

  variables {
    landing_zone_config_path        = "tests/fixtures/landing-zone-aws-minimal.yaml"
    platform_team_id                = "team-platform1"
    drift_team_id                   = "team-drift1"
    control_plane_approvers_team_id = "team-approvers1"
    saas_approvers_team_id          = "team-saasapprove1"
  }

  assert {
    condition = alltrue([
      for ws in ["aws-network", "aws-identity", "aws-shared-services", "aws-backup"] : !contains(keys(local.workspaces), ws)
    ]) && contains(keys(local.workspaces), "aws-organization") && contains(keys(local.workspaces), "aws-security")
    error_message = "aws.layers: [] must create aws-organization and aws-security only (plus aws-workload-<env>)."
  }

  assert {
    condition     = contains(keys(local.workspaces), "aws-workload-dev") && contains(keys(local.workspaces), "aws-workload-staging")
    error_message = "aws.layers must not change the aws-workload-<env> family (aws.workload_environments)."
  }

  # No run trigger, remote-state edge or drift entry names a dropped layer.
  assert {
    condition     = length([for k in keys(local.run_trigger_pairs) : k if can(regex("aws-(network|identity|shared-services|backup)", k))]) == 0 && contains(keys(local.run_trigger_pairs), "aws-security->aws-workload-dev")
    error_message = "Run triggers must keep aws-security -> aws-workload-<env> and drop every edge of a dropped layer."
  }
  assert {
    condition     = !contains(keys(local.consumer_names), "aws-network") && !contains(output.drift_workspaces, "aws-network") && !contains(output.drift_workspaces, "aws-backup")
    error_message = "A dropped layer must have no remote-state consumers and no drift entry."
  }

  # Without aws-network the workloads run standalone: tfc-admin sets
  # enable_network_hub = false on them.
  assert {
    condition     = local.workspace_vars["aws-workload-dev"]["enable_network_hub"].value == "false" && local.workspace_vars["aws-workload-dev"]["enable_network_hub"].hcl == true && local.workspace_vars["aws-workload-staging"]["enable_network_hub"].value == "false"
    error_message = "Without the network layer every aws-workload-<env> must get enable_network_hub = false (HCL)."
  }
}

run "aws_layers_absent_keeps_every_layer" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  }

  assert {
    condition     = alltrue([for ws in ["aws-network", "aws-identity", "aws-shared-services", "aws-backup"] : contains(keys(local.workspaces), ws)])
    error_message = "Without aws.layers every AWS layer workspace must exist."
  }

  assert {
    condition     = !contains(keys(local.workspace_vars["aws-workload-dev"]), "enable_network_hub") && contains(keys(local.run_trigger_pairs), "aws-network->aws-workload-dev")
    error_message = "With the network layer the workloads keep hub mode and the aws-network run trigger."
  }
}

# An explicit aws_layers wins over aws.layers in the config file.
run "aws_layers_variable_wins_over_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-aws-minimal.yaml"
    aws_layers               = ["network", "backup"]
  }

  assert {
    condition     = contains(keys(local.workspaces), "aws-network") && contains(keys(local.workspaces), "aws-backup") && !contains(keys(local.workspaces), "aws-identity") && !contains(keys(local.workspaces), "aws-shared-services")
    error_message = "aws_layers = [network, backup] must create aws-network and aws-backup only among the optional layers."
  }
}

run "aws_layers_rejects_unknown_layer" {
  command = plan

  variables {
    aws_layers = ["networking"]
  }

  expect_failures = [var.aws_layers]
}

# aws-workload-<env> in hub mode reads aws-network's state: without that
# workspace (and without aws.contracts.network) hub mode cannot plan.
run "aws_layers_without_network_rejects_hub_mode_workloads" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-aws-minimal.yaml"
    workspace_variables = {
      "aws-workload-dev" = { enable_network_hub = { value = "true", hcl = true } }
    }
  }

  expect_failures = [terraform_data.input_contract]
}

# aws.contracts.network supplies the hub contract, so the workloads read no
# aws-network state and keep hub mode.
run "aws_layers_without_network_keeps_hub_mode_with_a_network_contract" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-aws-minimal-contract.yaml"
    workspace_variables = {
      "aws-workload-dev" = { enable_network_hub = { value = "true", hcl = true } }
    }
  }

  assert {
    condition     = !contains(keys(local.workspaces), "aws-network") && !contains(keys(local.workspace_vars["aws-workload-staging"]), "enable_network_hub")
    error_message = "With aws.contracts.network tfc-admin must not force standalone mode."
  }
}

# ADO-20: org.tfc.policy_sets_waiver { reason, expires } in the config file
# waives the policy_sets_guard for a production estate without policy sets.
run "production_policy_sets_off_fails_from_config" {
  command = plan

  variables {
    tfc_plan           = "free"
    policy_sets_waiver = null
  }

  expect_failures = [terraform_data.policy_sets_guard]
}

run "config_policy_sets_waiver_passes" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/policy-sets-waiver-unquoted-date.yaml"
    policy_sets_waiver       = null
  }

  assert {
    condition     = !local.enable_policy_sets && local.policy_sets_waived && local.policy_sets_waiver_until == "2099-12-31T23:59:59Z"
    error_message = "org.tfc.policy_sets_waiver (unquoted YAML date) must waive the guard through its expiry day."
  }
}

run "config_policy_sets_waiver_expired_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-policy-sets-waiver-expired.yaml"
    policy_sets_waiver       = null
  }

  expect_failures = [terraform_data.policy_sets_guard]
}
