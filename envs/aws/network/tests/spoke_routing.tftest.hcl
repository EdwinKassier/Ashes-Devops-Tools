# aws.network.spoke_attachments reaches the aws-network-hub stage from the config
# file (the stage's own suite asserts the accept/associate/propagate wiring), and
# no spoke is wired when it is absent.

mock_provider "aws" {}

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  log_archive_bucket_name  = "ashes-org-log-archive"
  default_tags             = { CostCenter = "networking" }
  # Spokes need the inspection firewall (the stage rejects spokes without it).
  enable_network_firewall = true
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
      }
    }
  }
}

run "no_spokes_by_default" {
  command = plan

  assert {
    condition     = length(local.spoke_attachments) == 0 && length(module.aws_network_hub.spoke_attachment_route_tables) == 0
    error_message = "With no config and no variables no spoke is wired."
  }
}

run "spokes_reach_network_hub_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-spokes.yaml"
    landing_zone_name        = null
    log_archive_bucket_name  = null
    availability_zones       = ["eu-west-1a", "eu-west-1b"]
    regional_cidrs           = { eu-west-1 = "10.0.0.0/12", eu-west-2 = "10.16.0.0/12" }
  }

  assert {
    condition     = toset(keys(module.aws_network_hub.spoke_attachment_route_tables)) == toset(["dev", "prod"])
    error_message = "aws.network.spoke_attachments must reach the network-hub stage."
  }

  assert {
    condition     = local.spoke_attachments.dev.segment == "nonprod" && local.spoke_attachments.prod.accept == false
    error_message = "segment and accept must pass through from the config file."
  }
}

run "explicit_variable_beats_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-spokes.yaml"
    landing_zone_name        = null
    log_archive_bucket_name  = null
    availability_zones       = ["eu-west-1a", "eu-west-1b"]
    regional_cidrs           = { eu-west-1 = "10.0.0.0/12", eu-west-2 = "10.16.0.0/12" }
    spoke_attachments        = {}
  }

  assert {
    condition     = length(module.aws_network_hub.spoke_attachment_route_tables) == 0
    error_message = "An explicit spoke_attachments variable must win over the config file."
  }
}
