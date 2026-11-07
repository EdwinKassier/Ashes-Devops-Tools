# aws.network.vpn reaches the aws-network-hub stage from the config file and the
# VPN stays off when absent. Nothing secret is configured: AWS generates the
# tunnel keys.

mock_provider "aws" {}

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
      }
    }
  }
}

run "vpn_off_by_default" {
  command = plan

  assert {
    condition     = local.enable_vpn == false && length(module.aws_network_hub.vpn_tunnel_addresses) == 0
    error_message = "With no config and no variables the Site-to-Site VPN must be off."
  }
}

run "aws_vpn_reaches_network_hub_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-vpn.yaml"
    landing_zone_name        = null
    log_archive_bucket_name  = null
    availability_zones       = ["eu-west-1a", "eu-west-1b"]
    regional_cidrs           = { eu-west-1 = "10.0.0.0/12", eu-west-2 = "10.16.0.0/12" }
  }

  assert {
    condition     = local.enable_vpn == true && local.vpn.customer_gateway_ip == "203.0.113.10" && local.vpn.customer_gateway_bgp_asn == 65010 && local.vpn.static_routes_only == true && join(",", local.vpn.onprem_cidrs) == "192.168.0.0/16"
    error_message = "aws.network.vpn must reach the network-hub stage as enable_vpn and vpn."
  }
}

run "explicit_variable_beats_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-vpn.yaml"
    landing_zone_name        = null
    log_archive_bucket_name  = null
    availability_zones       = ["eu-west-1a", "eu-west-1b"]
    regional_cidrs           = { eu-west-1 = "10.0.0.0/12", eu-west-2 = "10.16.0.0/12" }
    enable_vpn               = false
  }

  assert {
    condition     = local.enable_vpn == false
    error_message = "An explicit enable_vpn must beat aws.network.vpn.enabled."
  }
}
