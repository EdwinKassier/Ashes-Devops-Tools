# Root-level contract test. Mocks all five aws providers (so no real credentials
# or role assumption happens) and overrides the aws-organization remote-state
# data source with a known cross-root contract. Asserts the root plans and that
# the keys the root consumes from remote state flow into the stage inputs.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape (organization_id / organization_root_id / management_account_id
# / account_ids[*] / account_role_arns[*]) the root depends on.

mock_provider "aws" {}
mock_provider "aws" { alias = "security_tooling" }
mock_provider "aws" { alias = "log_archive" }
mock_provider "aws" { alias = "forensics" }

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  management_account_id    = "111111111111" # C4 account guard
  log_archive_bucket_name  = "ashes-org-log-archive"
  # key_admin_arn / config_role_arn / aggregator_role_arn omitted: the defaults
  # (own-account tfc-apply key admin, Config SLR, created aggregator role) must plan.
  # Security Lake off so meta_store_manager_role_arn is not required.
  enable_security_lake = false
}

# The forensics CMK ARN flows through the stage into the incident-response
# module's forensics_kms_key_arn, whose count keys off whether that ARN is set.
# Under mock providers the CMK ARN is unknown at plan, which would make that
# count indeterminate ("Invalid count argument"); override the nested CMK output
# with a known ARN so the root can plan. Mirrors the stage-level tests.
override_module {
  target  = module.aws_security.module.forensics_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:555555555555:key/forensics-0000" }
}

run "consumes_remote_state_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        organization_id       = "o-abcdefghij"
        organization_root_id  = "r-abcd"
        management_account_id = "111111111111"
        account_ids = {
          security_tooling = "222222222222"
          log_archive      = "333333333333"
          shared_services  = "444444444444"
          forensics        = "555555555555"
        }
        account_role_arns = {
          security_tooling = "arn:aws:iam::222222222222:role/cross-account"
          log_archive      = "arn:aws:iam::333333333333:role/cross-account"
          forensics        = "arn:aws:iam::555555555555:role/cross-account"
        }
      }
    }
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization[0].outputs.organization_root_id == "r-abcd"
    error_message = "remote-state organization_root_id contract key must be readable by the root"
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization[0].outputs.account_ids["forensics"] == "555555555555"
    error_message = "remote-state account_ids must expose the forensics account the root consumes"
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization[0].outputs.account_role_arns["security_tooling"] != ""
    error_message = "remote-state account_role_arns must expose the security_tooling role the provider assumes"
  }
}

# landing_zone_name has no default and rejects the upstream placeholders.
run "rejects_placeholder_landing_zone_name" {
  command = plan

  variables {
    landing_zone_name = "ashes"
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        organization_id       = "o-abcdefghij"
        organization_root_id  = "r-abcd"
        management_account_id = "111111111111"
        account_ids = {
          security_tooling = "222222222222"
          log_archive      = "333333333333"
          shared_services  = "444444444444"
          forensics        = "555555555555"
        }
        account_role_arns = {
          security_tooling = "arn:aws:iam::222222222222:role/cross-account"
          log_archive      = "arn:aws:iam::333333333333:role/cross-account"
          forensics        = "arn:aws:iam::555555555555:role/cross-account"
        }
      }
    }
  }

  expect_failures = [var.landing_zone_name]
}

# Stage contract override (FAST-style): organization_contract replaces the
# aws-organization remote-state read entirely (no override_data here).
run "organization_contract_skips_remote_state" {
  command = plan

  variables {
    organization_contract = {
      organization_id       = "o-abcdefghij"
      organization_root_id  = "r-abcd"
      management_account_id = "111111111111"
      account_ids           = { security_tooling = "222222222222", log_archive = "333333333333", shared_services = "444444444444", forensics = "555555555555" }
      account_role_arns     = { security_tooling = "arn:aws:iam::222222222222:role/cross-account", log_archive = "arn:aws:iam::333333333333:role/cross-account", shared_services = "arn:aws:iam::444444444444:role/cross-account", forensics = "arn:aws:iam::555555555555:role/cross-account" }
    }
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_organization) == 0 && local.org.organization_root_id == "r-abcd" && local.org.account_ids["forensics"] == "555555555555"
    error_message = "a supplied organization_contract must skip the aws-organization read and feed the root"
  }
}

# File-level remote-state override for the profile runs below (run-level
# overrides above still take precedence).
override_data {
  target = data.terraform_remote_state.aws_organization
  values = {
    outputs = {
      organization_id       = "o-abcdefghij"
      organization_root_id  = "r-abcd"
      management_account_id = "111111111111"
      account_ids = {
        security_tooling = "222222222222"
        log_archive      = "333333333333"
        shared_services  = "444444444444"
        forensics        = "555555555555"
      }
      account_role_arns = {
        security_tooling = "arn:aws:iam::222222222222:role/cross-account"
        log_archive      = "arn:aws:iam::333333333333:role/cross-account"
        forensics        = "arn:aws:iam::555555555555:role/cross-account"
      }
    }
  }
}


# profile = starter keeps the core detective controls and drops the
# usage-scaling extras.
run "starter_profile_trims_cost_scaling_services" {
  command = plan

  variables {
    profile              = "starter"
    enable_security_lake = null
  }

  assert {
    condition = (
      local.enable_security_lake == false &&
      local.enabled_security_services == toset(["inspector"]) &&
      local.config_record_all_supported == false &&
      local.guardduty_enable_ebs_malware_protection == false
    )
    error_message = "starter must turn off Security Lake, Macie, record-all Config and EBS malware scanning."
  }
}

run "production_profile_keeps_full_stack" {
  command = plan

  variables {
    enable_security_lake        = null
    meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
  }

  assert {
    condition     = local.enable_security_lake == true && local.enabled_security_services == toset(["macie", "inspector"]) && local.config_record_all_supported == true
    error_message = "the default (production) profile must keep Security Lake, Macie and record-all Config."
  }
}

# The untouched default (production profile, no hand-made metastore role)
# must plan.
run "production_default_plans_without_meta_store_role" {
  command = plan

  variables {
    enable_security_lake = null
  }

  assert {
    condition     = local.enable_security_lake == true
    error_message = "the default production profile must plan with Security Lake on and no hand-made metastore role."
  }
}
