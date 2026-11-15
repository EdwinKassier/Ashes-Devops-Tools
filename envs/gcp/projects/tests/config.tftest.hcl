# Single-source configuration: with project_prefix / environments /
# organization_name / default_region / tfc_organization unset, the root reads
# them from the landing-zone config file (a fixture here, config/landing-zone.yaml
# in a real estate); explicit variables still win; a missing value or an
# untouched placeholder fails fast.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
}

override_data {
  target = data.terraform_remote_state.gcp_bootstrap
  values = {
    outputs = {
      contract = {
        admin_project_id = "cfgco-admin-abcd"
        suffix           = "abcd"
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_organization
  values = {
    outputs = {
      contract = {
        billing_account = "billingAccounts/000000-111111-222222"
        folders = {
          dev  = { id = "111", name = "folders/111", display_name = "dev" }
          prod = { id = "222", name = "folders/222", display_name = "Production" }
        }
        tag_values = {
          "environment-dev"                = "tagValues/1"
          "environment-prod"               = "tagValues/2"
          "data-classification-internal"   = "tagValues/902"
          "data-classification-restricted" = "tagValues/900000000004"
        }
      }
    }
  }
}

override_module {
  target = module.projects
  outputs = {
    projects        = {}
    project_ids     = { "dev-host" = "cfgco-dev-host-abcd", "prod-host" = "cfgco-prod-host-abcd" }
    project_numbers = { "dev-host" = "333333333333", "prod-host" = "444444444444" }
  }
}

run "values_come_from_config_file" {
  command = plan

  assert {
    condition     = local.project_prefix == "cfgco" && local.organization_name == "Config Co" && local.default_region == "europe-west2" && local.tfc_organization == "cfg-tfc"
    error_message = "unset scalars must fall back to org.prefix / org.display_name / org.regions.gcp / org.tfc.organization."
  }

  assert {
    condition     = toset(keys(output.environment_config)) == toset(["dev", "prod"])
    error_message = "environments must come from gcp.environments in the config file."
  }

  # Defaults applied during normalisation: region <- org.regions.gcp,
  # display_name <- key, is_production <- false; explicit fields kept.
  assert {
    condition     = output.environment_config["dev"].region == "europe-west2" && output.environment_config["prod"].region == "europe-west1" && output.environment_config["prod"].is_production && !output.environment_config["dev"].is_production
    error_message = "config environments must be normalised (region default, is_production default) without losing explicit fields."
  }

  assert {
    condition     = local.environments["dev"].display_name == "dev" && contains(local.environments["dev"].iam_group_role_bindings["devs@cfg.example.com"], "roles/viewer") && local.environments["dev"].labels.tier == "non-production"
    error_message = "display_name must default to the key and iam_group_role_bindings / labels must be carried through."
  }
}

run "explicit_variables_win_over_config" {
  command = plan

  variables {
    project_prefix = "acme"
    default_region = "us-central1"
    environments = {
      dev = {
        display_name            = "Development"
        region                  = "us-central1"
        cidr_block              = "10.10.0.0/16"
        budget_monthly_limit    = 100
        iam_group_role_bindings = {}
      }
    }
  }

  assert {
    condition     = local.project_prefix == "acme" && local.default_region == "us-central1" && keys(output.environment_config) == ["dev"]
    error_message = "an explicit variable must take precedence over the config file."
  }
}

run "missing_config_and_variables_fails" {
  command = plan

  variables {
    landing_zone_config_path = ""
  }

  expect_failures = [var.project_prefix, var.environments]
}

run "untouched_placeholder_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-placeholder.yaml"
  }

  expect_failures = [var.project_prefix]
}

# The shipped schema example parses (environments normalise cleanly) but its
# placeholders are rejected, so an untouched copy fails fast.
run "shipped_example_is_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "../../../config/landing-zone.example.yaml"
  }

  expect_failures = [var.project_prefix]
}

# Scaffold matrix: committed scaffolder output (make scaffold-fixtures) must plan.
run "scaffold_gcp_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp.yaml"
  }
}

run "scaffold_gcp_aws_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp-aws.yaml"
  }
}

run "scaffold_gcp_aws_saas_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp-aws-saas.yaml"
  }
}

# One environment on NCC (gcp.environments.<env>.network_connectivity) turns the
# NCC API on for the hub and every host project; the default fixture does not.
run "ncc_api_follows_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-ncc.yaml"
  }

  assert {
    condition     = local.enable_network_connectivity_center && toset(keys(local.ncc_project_services)) == toset(["shared-hub", "dev-host", "prod-host"])
    error_message = "Any environment with network_connectivity = ncc must enable the NCC API on shared-hub and every host project."
  }
}

run "ncc_api_off_without_ncc_config" {
  command = plan

  assert {
    condition     = !local.enable_network_connectivity_center && length(local.ncc_project_services) == 0
    error_message = "Without any NCC key in the config the NCC API must stay off."
  }
}

# Production is the is_production flag alone: a config environment without it
# fails the plan, naming the entry, instead of silently counting as non-prod.
run "config_environment_without_is_production_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-missing-is-production.yaml"
  }

  expect_failures = [var.environments]
}

# gcp.environments.<env>.data_classification and org.cost_center / org.owner
# from the config file (CMP-10, ARC-17).
run "data_classification_and_cost_labels_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.classified.yaml"
  }

  assert {
    condition = (
      output.contract.environment_config["prod"].tag_value_ids.data_classification == "tagValues/900000000004" &&
      local.project_environments["prod"].projects.host.tag_bindings == { data_classification = "tagValues/900000000004" } &&
      output.contract.environment_config["dev"].tag_value_ids.data_classification == "tagValues/902"
    )
    error_message = "each environment's host project must be bound to its data-classification tag value (prod restricted, dev the internal default)."
  }

  assert {
    condition     = local.gcp_default_labels["cost-center"] == "fin-42" && local.gcp_default_labels["owner"] == "data-team"
    error_message = "org.cost_center / org.owner must reach the provider default labels in label form (lowercase, other characters as '-')."
  }
}

# Re-audit 6 CMP-4: the contract publishes the class, and an environments
# variable cannot drop it.
run "contract_publishes_the_regulated_class" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated.yaml"
  }

  assert {
    condition     = output.contract.environment_config["prod"].compliance_class == "regulated" && output.contract.environment_config["dev"].compliance_class == "standard"
    error_message = "environment_config must carry each environment's compliance_class."
  }
}

run "environments_override_cannot_unmark_regulated" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated.yaml"
    environments = {
      prod = {
        display_name            = "Production"
        region                  = "europe-west2"
        cidr_block              = "10.30.0.0/16"
        budget_monthly_limit    = 1000
        iam_group_role_bindings = {}
        is_production           = true
      }
    }
  }

  expect_failures = [var.environments]
}
