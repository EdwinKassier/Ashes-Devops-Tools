# IPAM pool capacity and share scope: aws.network.regional_additional_cidrs and
# aws.network.ipam_share_ou_keys (or the variables) reach the network-hub stage.
# With neither set the pools keep the whole-organization share and one CIDR.

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
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  log_archive_bucket_name  = "ashes-org-log-archive"
  default_tags             = { CostCenter = "networking" }
}

override_data {
  target = data.terraform_remote_state.aws_organization
  values = {
    outputs = {
      contract = {
        organization_id       = "o-abcdefghij"
        management_account_id = "111111111111"
        account_ids           = { network = "666666666666" }
        account_role_arns     = { network = "arn:aws:iam::666666666666:role/cross-account" }
        ou_ids                = { Workloads = "ou-ab12-workload1", Security = "ou-ab12-security1" }
      }
    }
  }
}

run "defaults_keep_the_organization_share_and_one_cidr" {
  command = plan

  assert {
    condition     = local.ipam_share_principal_arns == null && length(local.regional_additional_cidrs) == 0
    error_message = "With no config and no variables the pools are shared with the whole organization and have no extra CIDR."
  }
}

run "variables_set_extra_cidrs_and_share_ous" {
  command = plan

  variables {
    regional_additional_cidrs = { eu-west-2 = ["10.80.0.0/12"] }
    ipam_share_ou_keys        = ["Workloads"]
    egress_cidr               = "10.80.0.0/16"
  }

  assert {
    condition     = join(",", local.ipam_share_principal_arns) == "arn:aws:organizations::111111111111:ou/o-abcdefghij/ou-ab12-workload1"
    error_message = "ipam_share_ou_keys must become OU ARNs built from the organization contract."
  }

  assert {
    condition     = module.aws_network_hub.hub_static_ipam_allocations["egress"] == "10.80.0.0/16"
    error_message = "A hub VPC inside an additional pool CIDR must be reserved there, so the extra CIDR reaches the stage."
  }
}

run "config_sets_extra_cidrs_and_share_ous" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-ipam-pool.yaml"
    landing_zone_name        = null
    log_archive_bucket_name  = null
  }

  assert {
    condition     = join(",", local.regional_additional_cidrs["eu-west-2"]) == "10.80.0.0/12" && join(",", local.ipam_share_principal_arns) == "arn:aws:organizations::111111111111:ou/o-abcdefghij/ou-ab12-workload1"
    error_message = "aws.network.regional_additional_cidrs and aws.network.ipam_share_ou_keys must be read from the config file."
  }
}

run "unknown_ou_key_fails_the_plan" {
  command = plan

  variables {
    ipam_share_ou_keys = ["Workloadz"]
  }

  expect_failures = [terraform_data.ipam_share_ou_keys]
}

run "rejects_invalid_additional_cidr" {
  command = plan

  variables {
    regional_additional_cidrs = { eu-west-2 = ["not-a-cidr"] }
  }

  expect_failures = [var.regional_additional_cidrs]
}

run "rejects_empty_share_list" {
  command = plan

  variables {
    ipam_share_ou_keys = []
  }

  expect_failures = [var.ipam_share_ou_keys]
}
