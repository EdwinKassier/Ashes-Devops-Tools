# Spoke-routing tests for the aws-workload stage.
#
# Unlike plan_assertions, the vpc child is NOT overridden here, so the real vpc
# module plans the spoke route tables from the stage's inputs; the stage outputs
# expose them and the routing contract for assertion.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  tgw_id                   = "tgw-000000000000abcd"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_archive_bucket_name  = "ashes-org-log-archive"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}

run "spoke_routes_to_tgw" {
  command = plan

  variables {
    environment           = "dev"
    tags                  = { Team = "payments" }
    tgw_destination_cidrs = ["0.0.0.0/0", "10.0.0.0/8"]
  }

  # One route table per tier per AZ (3 tiers x 2 AZs), owned by the vpc module
  # and surfaced through the stage. (The vpc module's own tests assert the
  # aws_route / endpoint-association resources it builds from these inputs.)
  assert {
    condition = alltrue([
      for t in ["private", "isolated", "tgw"] : length(output.route_table_ids_by_tier[t]) == 2
    ])
    error_message = "spoke VPC must own one route table per tier per AZ"
  }

  # The routing contract handed to the vpc module: private tier only, both
  # destinations, all via the shared TGW.
  assert {
    condition = (
      keys(output.tgw_routes) == ["private"] &&
      length(output.tgw_routes["private"]) == 2 &&
      alltrue([for r in output.tgw_routes["private"] : r.transit_gateway_id == "tgw-000000000000abcd"]) &&
      toset([for r in output.tgw_routes["private"] : r.destination_cidr_block]) == toset(["0.0.0.0/0", "10.0.0.0/8"])
    )
    error_message = "spoke private tier must route every tgw_destination_cidrs entry to the shared TGW (isolated tier excluded)"
  }

  # Name derived from environment; tags flow to the attachment.
  assert {
    condition = (
      output.name == "workload-dev" &&
      aws_ec2_transit_gateway_vpc_attachment.spoke[0].tags["Name"] == "workload-dev-spoke"
    )
    error_message = "name must default to workload-<environment> and tags must reach the TGW attachment"
  }
}

# Standalone mode (no aws-network layer): tgw_id = null plans the spoke VPC with
# no TGW attachment and no TGW routes, so the private tier stays local-only.
run "standalone_without_tgw" {
  command = plan

  variables {
    tgw_id      = null
    environment = "dev"
  }

  assert {
    condition = (
      length(aws_ec2_transit_gateway_vpc_attachment.spoke) == 0 &&
      length(output.tgw_routes) == 0 &&
      output.tgw_attachment_id == null &&
      length(output.route_table_ids_by_tier["private"]) == 2
    )
    error_message = "tgw_id = null must plan a standalone spoke: no TGW attachment, no TGW routes"
  }
}

run "unknown_route_tier_rejected" {
  command = plan

  variables {
    tgw_route_tiers = ["nosuchtier"]
  }

  expect_failures = [var.tgw_route_tiers]
}

run "ipam_default_plans_legacy_netmask_shape" {
  command = plan

  variables {
    ipam_pool_id = "ipam-pool-0123456789abcdef0"
  }

  assert {
    condition     = local.ipam_allocation == "netmask"
    error_message = "the default must keep the legacy pool + netmask_length shape (explicit CIDR would replace existing VPCs)"
  }
}

run "ipam_explicit_cidr_is_opt_in" {
  command = plan

  variables {
    ipam_pool_id       = "ipam-pool-0123456789abcdef0"
    ipam_explicit_cidr = true
  }

  assert {
    condition     = local.ipam_allocation == "explicit_cidr"
    error_message = "ipam_explicit_cidr must select the explicit-CIDR allocation"
  }
}
