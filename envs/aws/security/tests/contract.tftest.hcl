# Cross-root contract for the aws-security root: how it sources the
# aws-organization contract (organization_id / organization_root_id /
# management_account_id / account_ids / account_role_arns) from the three
# places it can come from, in precedence order:
#   1. var.organization_contract
#   2. aws.contracts.organization in the landing-zone config file
#   3. the aws-organization workspace's remote state (overridden here)
# plus the config-file fallbacks it shares with aws-organization / aws-network
# (management_account_id, log_archive_bucket_name, aws.enabled_regions,
# org.profile).

mock_provider "aws" {}
mock_provider "aws" { alias = "security_tooling" }
mock_provider "aws" { alias = "log_archive" }
mock_provider "aws" { alias = "forensics" }

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  management_account_id    = "111111111111"
  aws_overrides = {
    log_archive_bucket_name = "acme-org-log-archive"
    enable_security_lake    = false
  }
}

override_module {
  target  = module.aws_security.module.forensics_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:555555555555:key/forensics-0000" }
}

# Remote state carries more outputs than this root consumes; the root must
# project only the five contract fields it needs.
override_data {
  target = data.terraform_remote_state.aws_organization
  values = {
    outputs = {
      contract = {
        organization_id       = "o-abcdefghij"
        organization_root_id  = "r-abcd"
        management_account_id = "111111111111"
        ou_ids                = { Security = "ou-abcd-security00" }
        account_ids = {
          security_tooling = "222222222222"
          log_archive      = "333333333333"
          shared_services  = "444444444444"
          forensics        = "555555555555"
          network          = "666666666666"
        }
        account_role_arns = {
          security_tooling = "arn:aws:iam::222222222222:role/cross-account"
          log_archive      = "arn:aws:iam::333333333333:role/cross-account"
          forensics        = "arn:aws:iam::555555555555:role/cross-account"
        }
        tfc_plan_role_arns = {}
      }
    }
  }
}

run "remote_state_is_projected_onto_the_contract" {
  command = plan

  assert {
    condition     = local.read_organization && length(data.terraform_remote_state.aws_organization) == 1
    error_message = "with no organization_contract anywhere the aws-organization remote state must be read."
  }

  assert {
    condition     = toset(keys(local.org)) == toset(["organization_id", "organization_root_id", "management_account_id", "ou_ids", "account_ids", "account_role_arns"])
    error_message = "local.org must project the remote contract onto the shared aws organization_contract type (all six fields)."
  }

  assert {
    condition = (
      local.org.organization_root_id == "r-abcd" &&
      local.org.account_ids["security_tooling"] == "222222222222" &&
      local.org.account_ids["log_archive"] == "333333333333" &&
      local.org.account_ids["shared_services"] == "444444444444" &&
      local.org.account_role_arns["forensics"] == "arn:aws:iam::555555555555:role/cross-account"
    )
    error_message = "every account the stage consumes must flow from remote state into local.org."
  }

  # The forensics account ID is echoed through the security contract output.
  assert {
    condition     = output.forensics_account_id == "555555555555"
    error_message = "the forensics_account_id output must echo account_ids[forensics] from the organization contract."
  }
}

run "config_without_contract_still_reads_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-no-contract.yaml"
    management_account_id    = null
    aws_overrides = merge(var.aws_overrides, {
      log_archive_bucket_name = null
    })
  }

  assert {
    condition     = local.read_organization && local.org.organization_root_id == "r-abcd" && local.tfc_organization == "cfg-tfc"
    error_message = "a config file with no aws.contracts.organization must not suppress the remote-state read."
  }

  assert {
    condition     = local.management_account_id == "012345678901" && local.aws.log_archive_bucket_name == "cfgco-org-log-archive"
    error_message = "management_account_id / log_archive_bucket_name must fall back to the config file."
  }
}

run "config_contract_replaces_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    landing_zone_name        = null
    management_account_id    = null
    aws_overrides = merge(var.aws_overrides, {
      log_archive_bucket_name = null
      enable_security_lake    = null
    })
  }

  assert {
    condition     = !local.read_organization && length(data.terraform_remote_state.aws_organization) == 0
    error_message = "aws.contracts.organization in the config file must skip the aws-organization read."
  }

  assert {
    condition = (
      local.org.organization_id == "o-cfgcfgcfg0" && local.org.organization_root_id == "r-cfg0" &&
      local.org.account_ids["forensics"] == "055555555555" &&
      local.org.account_role_arns["security_tooling"] == "arn:aws:iam::022222222222:role/cross-account"
    )
    error_message = "the config-file contract must feed local.org (quoted IDs keep their leading zero)."
  }

  assert {
    condition = (
      local.landing_zone_name == "cfgco" && local.aws_region == "eu-west-1" &&
      join(",", local.aws_enabled_regions) == "eu-west-1,eu-west-2" &&
      local.management_account_id == "012345678901" &&
      local.aws.log_archive_bucket_name == "cfgco-org-log-archive"
    )
    error_message = "name / region / enabled regions / management account / log-archive bucket must fall back to the config file."
  }

  # org.profile = starter in the fixture trims the usage-scaling services.
  assert {
    condition     = local.profile == "starter" && local.enable_security_lake == false && local.enabled_security_services == toset(["inspector"])
    error_message = "org.profile from the config file must drive the profile-dependent toggles."
  }
}

run "variable_contract_beats_config_contract" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    organization_contract = {
      organization_id       = "o-varsvarsva"
      organization_root_id  = "r-vars"
      management_account_id = "111111111111"
      account_ids           = { security_tooling = "922222222222", log_archive = "933333333333", shared_services = "944444444444", forensics = "955555555555" }
      account_role_arns     = { security_tooling = "arn:aws:iam::922222222222:role/cross-account", log_archive = "arn:aws:iam::933333333333:role/cross-account", forensics = "arn:aws:iam::955555555555:role/cross-account" }
    }
  }

  assert {
    condition     = !local.read_organization && local.org.organization_root_id == "r-vars" && local.org.account_ids["forensics"] == "955555555555"
    error_message = "var.organization_contract must win over aws.contracts.organization."
  }

  assert {
    condition     = local.management_account_id == "111111111111" && local.aws.log_archive_bucket_name == "acme-org-log-archive" && local.landing_zone_name == "acme"
    error_message = "explicit variables must win over the config file."
  }
}

# notifications.emails becomes one email subscriber each on the
# security-notifications topic (and, by reuse, the CIS alarm topic).
run "emails_feed_security_topic" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
    landing_zone_name        = null
    management_account_id    = null
    aws_overrides = merge(var.aws_overrides, {
      log_archive_bucket_name = null
      enable_security_lake    = null
    })
  }

  assert {
    condition = (
      length(local.notification_subscribers) == 2 &&
      alltrue([for s in values(local.notification_subscribers) : s.protocol == "email"]) &&
      toset([for s in values(local.notification_subscribers) : s.endpoint]) == toset(["alerts@cfg.test", "oncall@cfg.test"])
    )
    error_message = "notifications.emails must become email subscribers of the security-notifications topic."
  }
}

# An explicit variable beats the config section.
run "explicit_subscribers_beat_notifications_emails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
    landing_zone_name        = null
    management_account_id    = null
    aws_overrides = merge(var.aws_overrides, {
      log_archive_bucket_name  = null
      enable_security_lake     = null
      notification_subscribers = { soc = { protocol = "https", endpoint = "https://soc.example.com/hook" } }
    })
  }

  assert {
    condition     = length(local.notification_subscribers) == 1 && contains(keys(local.notification_subscribers), "soc")
    error_message = "an explicit notification_subscribers must win over notifications.emails."
  }
}

# No section: the historical placeholder subscriber is kept.
run "no_section_is_noop" {
  command = plan

  assert {
    condition     = length(local.notification_subscribers) == 1 && local.notification_subscribers["secops"].endpoint == "secops@example.com"
    error_message = "without a notifications section the default placeholder subscriber must be unchanged."
  }
}

# Object pass-through precedence: a set aws_overrides key beats the config file
# (config keys and override-only keys alike) ...
run "override_wins_over_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    landing_zone_name        = null
    management_account_id    = null
    aws_overrides = {
      log_archive_bucket_name   = "override-org-log-archive"
      aws_enabled_regions       = ["us-east-1"]
      enabled_security_services = ["macie"]
      enable_incident_response  = false
    }
  }

  assert {
    condition     = local.aws.log_archive_bucket_name == "override-org-log-archive" && join(",", local.aws_enabled_regions) == "us-east-1" && local.enabled_security_services == toset(["macie"])
    error_message = "a set aws_overrides key must win over aws.* in config/landing-zone.yaml and over the profile default."
  }

  assert {
    condition     = output.contract.log_archive_bucket_name == "override-org-log-archive"
    error_message = "the overridden bucket name must reach the stage."
  }
}

# ... and an unset (or null) key keeps the config value (or the profile default).
run "unset_override_keeps_config_value" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    landing_zone_name        = null
    management_account_id    = null
    aws_overrides = {
      log_archive_bucket_name = null
      aws_enabled_regions     = null
    }
  }

  assert {
    condition     = local.aws.log_archive_bucket_name == "cfgco-org-log-archive" && join(",", local.aws_enabled_regions) == "eu-west-1,eu-west-2" && local.enabled_security_services == toset(["inspector"])
    error_message = "an unset aws_overrides key must keep the aws.* config value (and the starter profile default)."
  }

  assert {
    condition     = output.contract.log_archive_bucket_name == "cfgco-org-log-archive"
    error_message = "the config bucket name must reach the stage."
  }
}
