# Root-level contract test. Mocks the default aws provider (so no real
# credentials or role assumption happens) and overrides the aws-organization
# remote-state data source with a known cross-root contract. Asserts the keys
# the root consumes from remote state (organization_id, management_account_id,
# account_role_arns[network]) are readable and that the org ARN the root builds
# for RAM sharing is well-formed.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

mock_provider "aws" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  log_archive_bucket_name  = "ashes-org-log-archive"
  default_tags             = { CostCenter = "networking" }
}

run "consumes_remote_state_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        organization_id       = "o-abcdefghij"
        management_account_id = "111111111111"
        account_ids           = { network = "666666666666" }
        account_role_arns = {
          network = "arn:aws:iam::666666666666:role/cross-account"
        }
      }
    }
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization[0].outputs.organization_id == "o-abcdefghij"
    error_message = "remote-state organization_id contract key must be readable by the root"
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization[0].outputs.account_role_arns["network"] != ""
    error_message = "remote-state account_role_arns must expose the network role the provider assumes"
  }

  # Provider default_tags carry the canonical cost-allocation keys.
  assert {
    condition = (
      local.aws_default_tags["Workspace"] == "aws-network" &&
      local.aws_default_tags["ManagedBy"] == "terraform" &&
      alltrue([for k in ["CostCenter", "Environment", "Owner", "LandingZone"] : contains(keys(local.aws_default_tags), k)])
    )
    error_message = "aws provider default_tags must carry the canonical tag set"
  }

  # A default_tags override wins over the canonical value.
  assert {
    condition     = local.aws_default_tags["CostCenter"] == "networking"
    error_message = "var.default_tags must be merged last so it can override canonical tags"
  }

  assert {
    condition     = local.org_arn == "arn:aws:organizations::111111111111:organization/o-abcdefghij"
    error_message = "org_arn must be built from management_account_id and organization_id for RAM org-wide sharing"
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
        management_account_id = "111111111111"
        account_ids           = { network = "666666666666" }
        account_role_arns = {
          network = "arn:aws:iam::666666666666:role/cross-account"
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
      management_account_id = "111111111111"
      account_ids           = { network = "666666666666" }
    }
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_organization) == 0 && local.org_arn == "arn:aws:organizations::111111111111:organization/o-abcdefghij"
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
      management_account_id = "111111111111"
      account_ids           = { network = "666666666666" }
      account_role_arns = {
        network = "arn:aws:iam::666666666666:role/cross-account"
      }
    }
  }
}


# profile = starter drops the Network Firewall unless explicitly enabled.
run "starter_profile_drops_network_firewall" {
  command = plan

  variables {
    profile = "starter"
  }

  assert {
    condition     = local.enable_network_firewall == false
    error_message = "the starter profile must default enable_network_firewall to false."
  }
}

run "explicit_toggle_beats_profile" {
  command = plan

  variables {
    profile                 = "starter"
    enable_network_firewall = true
  }

  assert {
    condition     = local.enable_network_firewall == true
    error_message = "an explicit enable_network_firewall must win over the profile."
  }
}

run "production_profile_is_the_default" {
  command = plan

  assert {
    condition     = local.profile == "production" && local.enable_network_firewall == true
    error_message = "with no profile set the production stack (Network Firewall on) must be the default."
  }
}

# Production egress fails closed. The alert-only failure is proven in the
# stage's production_egress tests (expect_failures cannot name a child-module
# object); the root runs below prove the gate wiring and that it plans when
# satisfied.
run "production_profile_with_seeded_allowlist_plans" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-production-allowlist.yaml"
  }

  assert {
    condition     = local.enforce_egress_allowlist == true && length(local.network_firewall_egress_domain_allowlist) == 4
    error_message = "production must enforce the allowlist and read it from config."
  }
}

run "starter_profile_unaffected" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-starter-prod-env.yaml"
  }

  assert {
    condition     = local.enforce_egress_allowlist == false
    error_message = "the starter profile must not enforce the egress gate."
  }
}

run "waiver_plans" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-production-waived.yaml"
  }

  assert {
    condition     = local.enforce_egress_allowlist == true && local.egress_alert_only_waived == true
    error_message = "the waiver must plan with the gate still on."
  }
}
