# Presets named in config/landing-zone.yaml (examples/presets/<name>.yaml) and
# their parity with the -var-file form (examples/presets/<name>.tfvars).

# A planned peering's state is unknown, which leaves check.hub_peering_active
# unknown, and terraform test fails a plan run on an unknown check (a real plan
# only warns). ACTIVE is what a peered environment reports.
mock_provider "google" {
  mock_resource "google_compute_network_peering" {
    override_during = plan
    defaults = {
      state = "ACTIVE"
    }
  }
}
mock_provider "google-beta" {}
# tfe serves only the SaaS secret bridge (ephemeral "tfe_outputs"); mocked so
# no run contacts HCP Terraform.
mock_provider "tfe" {}

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
        folder_id           = "333"
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
  # Standalone production cannot use the hub egress proxy (ARC-4).
  production_egress_proxy_waiver = {
    reason  = "Test suite: standalone, no hub egress proxy."
    expires = "2099-12-31"
  }
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
          folder_id           = "111"
          host_project_id     = "acme-dev-host-abcd"
          host_project_number = "222222222222"
          is_production       = false
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
          folder_id           = "111"
          host_project_id     = "acme-dev-host-abcd"
          host_project_number = "222222222222"
          is_production       = false
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

# ── compliance_class: regulated (CMP-7) ─────────────────────────────────────
# gcp.environments.<env>.compliance_class: regulated applies the
# regulated-gcp-workload preset to that environment only, and guards refuse any
# explicit variable that weakens it.

run "regulated_env_applies_regulated_preset" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = true
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  assert {
    condition = (
      local.compliance_class == "regulated" &&
      !local.vpc_sc_enable_dry_run &&
      local.enable_cloud_armor &&
      local.enable_owasp_rules &&
      local.flow_log_sampling == 1 &&
      local.flow_logs_retention_days == 365
    )
    error_message = "compliance_class: regulated must apply the regulated preset: enforced VPC-SC, Cloud Armor with OWASP rules, full flow-log sampling and 365-day retention."
  }

  assert {
    condition     = module.environment.components.cloud_armor && length(module.environment.components.vpc_sc_perimeters) > 0 && module.environment.components.psc_target == "vpc-sc"
    error_message = "The regulated preset must reach the environment stage (Cloud Armor on, an enforced perimeter, so PSC targets vpc-sc)."
  }

  # CMP-8: a regulated environment gets the Backup and DR vault, unlocked.
  assert {
    condition     = local.enable_backup_vault && module.environment.components.backup_vault && local.backup_vault_enforced_retention_days == 35 && local.backup_vault_lock_effective_time == null
    error_message = "compliance_class: regulated must turn the Backup and DR vault on (35-day enforced retention, no lock)."
  }

  # CMP-12: a regulated environment's app-service databases need a CMEK.
  assert {
    condition     = local.regulated && local.require_database_cmek
    error_message = "compliance_class: regulated must require a CMEK on app-service databases."
  }
}

run "regulated_env_rejects_dry_run_perimeter" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    vpc_sc_enable_dry_run    = true
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = false
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  # is_production is false: the regulated guard alone stops the plan.
  expect_failures = [terraform_data.regulated_perimeter_guard, terraform_data.compliance_class_guard]
}

run "regulated_env_needs_a_perimeter" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
  }

  # The file-level contract has no vpc_sc_access_policy_id: no perimeter. Its
  # is_production is false, so the CMP-1 guard fails too.
  expect_failures = [terraform_data.regulated_perimeter_guard, terraform_data.compliance_class_guard]
}

run "regulated_env_refuses_the_production_waiver" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    vpc_sc_enable_dry_run    = true
    production_vpc_sc_dry_run_waiver = {
      reason  = "first rollout"
      expires = "2999-12-31"
    }
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = true
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  # The waiver satisfies the production guard, never the regulated one.
  expect_failures = [terraform_data.regulated_perimeter_guard]
}

run "regulated_env_refuses_reduced_flow_log_sampling" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    log_config_flow_sampling = 0.5
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = false
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  expect_failures = [terraform_data.regulated_flow_logs_guard, terraform_data.compliance_class_guard]
}

run "regulated_env_refuses_short_flow_log_retention" {
  command = plan

  variables {
    landing_zone_config_path     = "tests/fixtures/landing-zone-regulated.yaml"
    vpc_flow_logs_retention_days = 90
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = false
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  expect_failures = [terraform_data.regulated_flow_logs_guard, terraform_data.compliance_class_guard]
}

run "standard_env_in_a_regulated_estate_is_unchanged" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    environment              = "dev"
    projects_contract = {
      environment_config = {
        dev = {
          folder_id           = "111"
          host_project_id     = "acme-dev-host-abcd"
          host_project_number = "222222222222"
          is_production       = false
          region              = "europe-west2"
          cidr_block          = "10.10.0.0/16"
        }
      }
    }
  }

  assert {
    condition = (
      local.compliance_class == "standard" &&
      length(local.preset_names) == 0 &&
      local.vpc_sc_enable_dry_run &&
      !local.enable_cloud_armor &&
      local.flow_log_sampling == 0.1 &&
      local.flow_logs_retention_days == 30 &&
      !local.enable_backup_vault &&
      !module.environment.components.backup_vault &&
      !local.require_database_cmek
    )
    error_message = "A standard environment in a regulated estate must keep today's defaults (no backup vault, no CMEK requirement)."
  }
}

# A regulated environment keeps Cloud Armor and its OWASP rules: an explicit
# variable may not turn either off.
run "regulated_env_refuses_disabled_cloud_armor" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    enable_cloud_armor       = false
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = false
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  expect_failures = [terraform_data.regulated_cloud_armor_guard, terraform_data.compliance_class_guard]
}

run "regulated_env_refuses_disabled_owasp_rules" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    enable_owasp_rules       = false
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = false
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  expect_failures = [terraform_data.regulated_cloud_armor_guard, terraform_data.compliance_class_guard]
}

# CMP-8: a regulated environment may not switch the Backup and DR vault off.
run "regulated_env_refuses_disabled_backup_vault" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    enable_backup_vault      = false
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = false
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  expect_failures = [terraform_data.regulated_backup_vault_guard, terraform_data.compliance_class_guard]
}

# A standard environment opts in through gcp.environments.<env>.backup_vault;
# the lock time is read from the config file only.
run "backup_vault_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-backup-vault.yaml"
    environment              = "dev"
    projects_contract = {
      environment_config = {
        dev = {
          folder_id           = "111"
          host_project_id     = "acme-dev-host-abcd"
          host_project_number = "222222222222"
          is_production       = false
          region              = "europe-west2"
          cidr_block          = "10.10.0.0/16"
        }
      }
    }
  }

  assert {
    condition = (
      local.compliance_class == "standard" &&
      local.enable_backup_vault &&
      module.environment.components.backup_vault &&
      local.backup_vault_enforced_retention_days == 90 &&
      local.backup_vault_lock_effective_time == "2027-06-01T00:00:00Z"
    )
    error_message = "gcp.environments.<env>.backup_vault must turn the vault on with its retention and lock time."
  }
}

# An explicit variable wins over the config file.
run "backup_vault_variable_wins" {
  command = plan

  variables {
    landing_zone_config_path             = "tests/fixtures/landing-zone-backup-vault.yaml"
    environment                          = "dev"
    enable_backup_vault                  = false
    backup_vault_enforced_retention_days = 60
    projects_contract = {
      environment_config = {
        dev = {
          folder_id           = "111"
          host_project_id     = "acme-dev-host-abcd"
          host_project_number = "222222222222"
          is_production       = false
          region              = "europe-west2"
          cidr_block          = "10.10.0.0/16"
        }
      }
    }
  }

  assert {
    condition     = !local.enable_backup_vault && !module.environment.components.backup_vault && local.backup_vault_enforced_retention_days == 60
    error_message = "enable_backup_vault and backup_vault_enforced_retention_days must win over the config file."
  }
}

run "unknown_compliance_class_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/schema-invalid-compliance-class.yaml"
  }

  expect_failures = [terraform_data.compliance_class_guard]
}

run "regulated_preset_yaml_matches_tfvars" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = true
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  assert {
    condition = (
      { for m in regexall("(?m)^([a-z][a-z0-9_]*)[ \\t]*=[ \\t]*([^#\\r\\n]*[^#\\s])", file("../../../examples/presets/regulated-gcp-workload.tfvars")) : m[0] => trim(m[1], "\"") } ==
      { for k, v in local.preset : k => tostring(v) }
    )
    error_message = "examples/presets/regulated-gcp-workload.yaml and .tfvars disagree: keep their values identical."
  }

  assert {
    condition     = join(",", local.preset_names) == "regulated-gcp-workload" && length(local.preset) == 5
    error_message = "A regulated environment must load the regulated preset with its five values."
  }
}

# CMP-1: a regulated environment that is not production fails the plan, and
# only through the compliance class guard.
run "regulated_env_must_be_production" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    projects_contract = {
      environment_config = {
        prod = {
          folder_id               = "333"
          host_project_id         = "acme-prod-host-abcd"
          host_project_number     = "333333333333"
          region                  = "europe-west2"
          cidr_block              = "10.30.0.0/16"
          is_production           = false
          vpc_sc_access_policy_id = "555555555"
        }
      }
    }
  }

  expect_failures = [terraform_data.compliance_class_guard]
}
