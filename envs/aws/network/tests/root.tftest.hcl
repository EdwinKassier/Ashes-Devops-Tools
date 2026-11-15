# Root-level contract test. Mocks the default aws provider (so no real
# credentials or role assumption happens) and overrides the aws-organization
# remote-state data source with a known cross-root contract. Asserts the keys
# the root consumes from remote state (organization_id, management_account_id,
# account_role_arns[network]) are readable and that the org ARN the root builds
# for RAM sharing is well-formed.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

# The root reads data.aws_availability_zones when no zone names are set (azs.tf).
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
      zone_ids = ["euw2-az2", "euw2-az3", "euw2-az1"]
    }
  }
}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  alarm_subscriber_emails  = ["netops@acme.io"]
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
        contract = {
          organization_id       = "o-abcdefghij"
          management_account_id = "111111111111"
          account_ids           = { network = "666666666666" }
          account_role_arns = {
            network = "arn:aws:iam::666666666666:role/cross-account"
          }
        }
      }
    }
  }

  assert {
    condition     = local.org.organization_id == "o-abcdefghij"
    error_message = "remote-state organization_id contract key must be readable by the root"
  }

  assert {
    condition     = local.org.account_role_arns["network"] != ""
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
        contract = {
          organization_id       = "o-abcdefghij"
          management_account_id = "111111111111"
          account_ids           = { network = "666666666666" }
          account_role_arns = {
            network = "arn:aws:iam::666666666666:role/cross-account"
          }
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
      contract = {
        organization_id       = "o-abcdefghij"
        management_account_id = "111111111111"
        account_ids           = { network = "666666666666" }
        account_role_arns = {
          network = "arn:aws:iam::666666666666:role/cross-account"
        }
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
    condition     = local.enforce_egress_allowlist == true && length(local.network_firewall_egress_domain_allowlist) == 6
    error_message = "production must enforce the allowlist and read it from config."
  }

  # ARC-1: the extra internal ranges and the custom rules come from config.
  assert {
    condition     = local.network_firewall_internal_pass_cidrs == tolist(["192.168.0.0/16"]) && startswith(local.network_firewall_suricata_rules, "pass tcp $HOME_NET any -> 203.0.113.10 22")
    error_message = "aws.network.internal_pass_cidrs and aws.network.suricata_rules must reach the firewall."
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

  assert {
    condition     = local.vpc_endpoint_policy_mode == "org_principals" && length(local.cfg.workload_regulated) == 0
    error_message = "without a regulated environment or the config key, the endpoint policy must stay principal-only."
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

# compliance_class: regulated (CMP-7). One regulated AWS workload environment
# forces the egress gate and the Network Firewall for the shared hub, on any
# profile, and refuses the alert-only waiver and the opt-outs.
run "regulated_workload_forces_egress_gate" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
  }

  assert {
    condition     = join(",", local.cfg.workload_regulated) == "pci" && local.enforce_egress_allowlist == true && local.enable_network_firewall == true
    error_message = "a regulated AWS workload env must force the egress gate and the Network Firewall, even on the starter profile."
  }

  assert {
    condition     = local.vpc_endpoint_policy_mode == "org_principals_and_resources"
    error_message = "aws.network.vpc_endpoint_policy_mode from the config file must reach the root."
  }
}

# A regulated estate on the principal-only endpoint policy plans with a
# warning (the resource-org policy is PREVIEW), never a failure.
run "regulated_estate_warns_on_principal_only_endpoints" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    vpc_endpoint_policy_mode = "org_principals"
  }

  expect_failures = [check.regulated_endpoint_policy]
}

run "regulated_refuses_waiver" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated-waived.yaml"
  }

  expect_failures = [var.egress_alert_only_waived]
}

run "regulated_refuses_disabled_egress_gate" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    enforce_egress_allowlist = false
  }

  expect_failures = [var.enforce_egress_allowlist]
}

run "regulated_refuses_disabled_network_firewall" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated.yaml"
    enable_network_firewall  = false
  }

  expect_failures = [var.enable_network_firewall]
}

run "unknown_compliance_class_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/schema-invalid-compliance-class.yaml"
  }

  expect_failures = [var.enforce_egress_allowlist]
}

# Hub network alarms (ARC-15): production needs a real subscriber or a topic.
run "production_alarms_without_subscriber_fail" {
  command = plan

  variables {
    alarm_subscriber_emails = []
  }

  expect_failures = [terraform_data.alarm_contact_guard]
}

run "production_alarms_reject_a_placeholder_address" {
  command = plan

  variables {
    alarm_subscriber_emails = ["secops@example.com"]
  }

  expect_failures = [terraform_data.alarm_contact_guard]
}

run "production_alarms_accept_a_supplied_topic" {
  command = plan

  variables {
    alarm_subscriber_emails = []
    alarm_sns_topic_arn     = "arn:aws:sns:eu-west-2:666666666666:ops-alerts"
  }

  assert {
    condition     = local.alarm_contact_required
    error_message = "the default (production) profile must require an alarm contact, so this run proves the topic satisfies the guard"
  }
}

run "starter_alarms_may_have_no_subscriber" {
  command = plan

  variables {
    profile                 = "starter"
    alarm_subscriber_emails = []
  }

  assert {
    condition     = !local.alarm_contact_required
    error_message = "a starter estate without production workloads only warns"
  }
}

run "alarm_subscribers_follow_notifications_emails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
    alarm_subscriber_emails  = null
  }

  assert {
    condition     = local.alarm_subscriber_emails == tolist(["secops@acme.io"])
    error_message = "notifications.emails must feed the hub alarm subscribers when the variable is unset"
  }
}

# CMP-1: a regulated environment must be production, or it misses the
# production controls that key on is_production.
run "regulated_not_production_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regulated-not-production.yaml"
  }

  expect_failures = [var.enforce_egress_allowlist]
}
