# Presets named in config/landing-zone.yaml (examples/presets/<name>.yaml) and
# their parity with the -var-file form (examples/presets/<name>.tfvars).

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_prefix       = "acme"
  environment          = "prod"
  tfc_organization     = "acme-tfc"
  monthly_budget_limit = 0
  organization_contract = {
    org_id               = "123456789012"
    billing_account      = "billingAccounts/000000-111111-222222"
    admin_project_number = "111111111111"
  }
  projects_contract = {
    environment_config = {
      prod = {
        folder_id           = "folders/333"
        host_project_id     = "acme-prod-host-abcd"
        host_project_number = "333333333333"
        region              = "europe-west2"
        cidr_block          = "10.30.0.0/16"
        # false keeps the vpc_sc_enforced_in_prod check out of these runs.
        is_production = false
      }
    }
  }
  enable_network_hub = false
}

# The mock provider returns no zones, which trips the spoke network's postcondition.
override_data {
  target = module.environment.module.host.data.google_compute_zones.available
  values = {
    names = ["europe-west2-a", "europe-west2-b", "europe-west2-c"]
  }
}

run "no_presets_keep_safe_defaults" {
  command = plan

  variables {
    landing_zone_config_path = ""
  }

  assert {
    condition     = local.vpc_sc_enable_dry_run && !local.enable_cloud_armor && !local.enable_owasp_rules
    error_message = "Without presets the defaults stay dry-run VPC-SC, no Cloud Armor."
  }
}

run "per_environment_preset_applies" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-presets.yaml"
  }

  assert {
    condition     = !local.vpc_sc_enable_dry_run && local.enable_cloud_armor && local.enable_owasp_rules
    error_message = "gcp.workload.presets_by_environment.prod = [prod-gcp-workload] must harden prod."
  }

  assert {
    condition     = module.environment.components.cloud_armor
    error_message = "The preset's enable_cloud_armor must reach the spoke network."
  }
}

run "preset_does_not_apply_to_other_environments" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-presets.yaml"
    environment              = "dev"
    projects_contract = {
      environment_config = {
        dev = {
          folder_id           = "folders/111"
          host_project_id     = "acme-dev-host-abcd"
          host_project_number = "222222222222"
          region              = "europe-west2"
          cidr_block          = "10.10.0.0/16"
        }
      }
    }
  }

  assert {
    condition     = local.vpc_sc_enable_dry_run && !local.enable_cloud_armor
    error_message = "A prod-only preset must not harden dev."
  }
}

run "top_level_presets_apply_to_every_environment" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-presets-global.yaml"
    environment              = "dev"
    projects_contract = {
      environment_config = {
        dev = {
          folder_id           = "folders/111"
          host_project_id     = "acme-dev-host-abcd"
          host_project_number = "222222222222"
          region              = "europe-west2"
          cidr_block          = "10.10.0.0/16"
        }
      }
    }
  }

  assert {
    condition     = !local.vpc_sc_enable_dry_run && local.enable_cloud_armor && local.enable_owasp_rules
    error_message = "A top-level `presets` entry applies to every gcp-workload-<env> workspace."
  }
}

run "explicit_variable_beats_preset" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-presets.yaml"
    vpc_sc_enable_dry_run    = true
  }

  assert {
    condition     = local.vpc_sc_enable_dry_run && local.enable_cloud_armor
    error_message = "An explicit variable must win over the preset for that key only."
  }
}

# The YAML twin (as loaded by this root) and the -var-file form must set the
# same keys to the same values (uncommented `key = value` lines of the .tfvars).
run "preset_yaml_matches_tfvars" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-presets.yaml"
  }

  assert {
    condition = (
      { for m in regexall("(?m)^([a-z][a-z0-9_]*)[ \\t]*=[ \\t]*([^#\\r\\n]*[^#\\s])", file("../../../examples/presets/prod-gcp-workload.tfvars")) : m[0] => trim(m[1], "\"") } ==
      { for k, v in local.preset : k => tostring(v) }
    )
    error_message = "examples/presets/prod-gcp-workload.yaml and .tfvars disagree: keep their values identical."
  }

  assert {
    condition     = length(local.preset_documents) == 1 && length(local.preset) == 3
    error_message = "The listed preset must load with its three values."
  }
}
