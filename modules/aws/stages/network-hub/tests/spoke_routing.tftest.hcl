# Workload spoke routing: each listed spoke attachment is accepted, associated
# with its segment table and propagated into the inspection table, and the hub
# gains the inspection->egress and shared->inspection routes the spokes need.
# Empty spoke_attachments (the default) plans none of it. Same stubbing as
# plan_assertions.tftest.hcl.

mock_provider "aws" {}

variables {
  org_id                   = "o-abc1234567"
  org_arn                  = "arn:aws:organizations::111111111111:organization/o-abc1234567"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_bucket_name          = "ashes-org-log-archive"
}

override_module {
  target = module.inspection_vpc
  outputs = {
    vpc_id   = "vpc-inspection000001"
    vpc_cidr = "10.0.0.0/16"
    subnet_ids_by_tier = {
      firewall = ["subnet-insp-fw-a", "subnet-insp-fw-b"]
      tgw      = ["subnet-insp-tgw-a", "subnet-insp-tgw-b"]
      private  = ["subnet-insp-prv-a", "subnet-insp-prv-b"]
    }
    route_table_ids_by_tier = {
      firewall = ["rtb-insp-fw-a", "rtb-insp-fw-b"]
      tgw      = ["rtb-insp-tgw-a", "rtb-insp-tgw-b"]
      private  = ["rtb-insp-prv-a", "rtb-insp-prv-b"]
    }
  }
}

override_module {
  target = module.egress_vpc
  outputs = {
    vpc_id   = "vpc-egress0000000001"
    vpc_cidr = "10.1.0.0/16"
    subnet_ids_by_tier = {
      public  = ["subnet-egr-pub-a", "subnet-egr-pub-b"]
      tgw     = ["subnet-egr-tgw-a", "subnet-egr-tgw-b"]
      private = ["subnet-egr-prv-a", "subnet-egr-prv-b"]
    }
    route_table_ids_by_tier = {
      public  = ["rtb-egr-pub-a", "rtb-egr-pub-b"]
      tgw     = ["rtb-egr-tgw-a", "rtb-egr-tgw-b"]
      private = ["rtb-egr-prv-a", "rtb-egr-prv-b"]
    }
  }
}

override_module {
  target = module.transit_gateway
  outputs = {
    tgw_id = "tgw-000000000000abcd"
    route_table_ids = {
      prod       = "tgw-rtb-prod00000000"
      nonprod    = "tgw-rtb-nonprod00000"
      inspection = "tgw-rtb-inspection00"
      shared     = "tgw-rtb-shared000000"
      hybrid     = "tgw-rtb-hybrid000000"
    }
    attachment_ids = {
      inspection = "tgw-attach-insp00000"
      egress     = "tgw-attach-egress000"
    }
  }
}

override_module {
  target  = module.ipam
  outputs = { regional_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } }
}

override_module {
  target  = module.route53_resolver
  outputs = { resolver_profile_id = "rp-0000000000000000" }
}

override_module {
  target  = module.vpc_endpoints
  outputs = { phz_id = "Z0000000000000000000" }
}

override_module {
  target = module.network_firewall
  outputs = {
    firewall_arn          = "arn:aws:network-firewall:eu-west-2:111111111111:firewall/inspection"
    firewall_endpoint_ids = ["vpce-fw-a", "vpce-fw-b"]
    firewall_endpoint_ids_by_az = {
      "eu-west-2a" = "vpce-fw-a"
      "eu-west-2b" = "vpce-fw-b"
    }
  }
}
override_module { target = module.network_access_analyzer }

run "no_spokes_is_a_noop" {
  command = apply

  assert {
    condition = (
      length(aws_ec2_transit_gateway_vpc_attachment_accepter.spoke) == 0 &&
      length(aws_ec2_transit_gateway_route_table_association.spoke) == 0 &&
      length(aws_ec2_transit_gateway_route_table_propagation.spoke) == 0 &&
      !contains(keys(output.tgw_inspection_routes), "inspection:default") &&
      !contains(keys(output.tgw_inspection_routes), "shared:spokes") &&
      length(output.spoke_attachment_route_tables) == 0
    )
    error_message = "spoke_attachments = {} (the default) must plan no spoke wiring and no extra hub routes."
  }
}

run "spokes_are_accepted_associated_and_propagated" {
  command = apply

  variables {
    spoke_attachments = {
      prod = { attachment_id = "tgw-attach-0123456789abcdef0", segment = "prod" }
      dev  = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod" }
    }
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment_accepter.spoke) == 2 && alltrue([for a in aws_ec2_transit_gateway_vpc_attachment_accepter.spoke : !a.transit_gateway_default_route_table_association && !a.transit_gateway_default_route_table_propagation])
    error_message = "every spoke attachment must be accepted by the TGW owner, without default-table association/propagation."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.spoke["prod"].transit_gateway_route_table_id == "tgw-rtb-prod00000000" && aws_ec2_transit_gateway_route_table_association.spoke["dev"].transit_gateway_route_table_id == "tgw-rtb-nonprod00000"
    error_message = "each spoke must associate with its own segment table (prod / nonprod), never the other."
  }

  assert {
    condition     = alltrue([for p in aws_ec2_transit_gateway_route_table_propagation.spoke : p.transit_gateway_route_table_id == "tgw-rtb-inspection00"]) && length(aws_ec2_transit_gateway_route_table_propagation.spoke) == 2
    error_message = "spoke CIDRs must propagate into the inspection table only (prod and nonprod never learn each other)."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_propagation.spoke["prod"].transit_gateway_attachment_id == "tgw-attach-0123456789abcdef0"
    error_message = "the propagation must use the spoke's attachment ID."
  }

  assert {
    condition = (
      output.tgw_inspection_routes["inspection:default"].route_table == "inspection" &&
      output.tgw_inspection_routes["inspection:default"].attachment == "egress" &&
      output.tgw_inspection_routes["inspection:default"].cidr == "0.0.0.0/0"
    )
    error_message = "inspected internet-bound traffic must default-route from the inspection table to the egress attachment."
  }

  assert {
    condition = (
      output.tgw_inspection_routes["shared:spokes"].route_table == "shared" &&
      output.tgw_inspection_routes["shared:spokes"].attachment == "inspection" &&
      output.tgw_inspection_routes["shared:spokes"].cidr == "10.0.0.0/8"
    )
    error_message = "egress replies to the spokes (top_cidr) must route through inspection from the shared table."
  }

  assert {
    condition     = output.tgw_inspection_routes["prod:default"].attachment == "inspection" && output.tgw_inspection_routes["nonprod:default"].attachment == "inspection"
    error_message = "the spoke segment defaults must still point at inspection."
  }
}

run "already_accepted_spoke_is_not_reaccepted" {
  command = apply

  variables {
    spoke_attachments = {
      dev = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod", accept = false }
    }
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment_accepter.spoke) == 0 && length(aws_ec2_transit_gateway_route_table_association.spoke) == 1
    error_message = "accept = false must skip the accepter but still associate the spoke."
  }
}

run "spoke_segment_must_be_prod_or_nonprod" {
  command = plan

  variables {
    spoke_attachments = {
      dev = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "shared" }
    }
  }

  expect_failures = [var.spoke_attachments]
}

run "spoke_attachment_id_format" {
  command = plan

  variables {
    spoke_attachments = {
      dev = { attachment_id = "vpc-0fedcba9876543210", segment = "nonprod" }
    }
  }

  expect_failures = [var.spoke_attachments]
}

run "spoke_attachment_ids_unique" {
  command = plan

  variables {
    spoke_attachments = {
      dev = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod" }
      qa  = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod" }
    }
  }

  expect_failures = [var.spoke_attachments]
}
