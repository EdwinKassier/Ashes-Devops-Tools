# Plan-assertion tests for the aws-network-hub stage.
#
# A single mock provider (the stage has one default provider, no aliases). The
# composition threads COMPUTED subnet ids from the two vpc children into the
# transit-gateway attachments, the network-firewall subnets, the vpc-endpoints
# and resolver, and the stage-level NAT for_each. Under mock those ids are
# unknown at plan, which would break the NAT/attachment for_each. So we
# override_module the vpc children with KNOWN vpc ids and known
# subnet_ids_by_tier maps, and override the transit_gateway child with known
# route_table_ids. That makes the for_each keys known and lets us assert the
# OUTPUT WIRING (input <- output edges) concretely under `command = apply`.

mock_provider "aws" {}

variables {
  org_id                   = "o-abc1234567"
  org_arn                  = "arn:aws:organizations::111111111111:organization/o-abc1234567"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_bucket_name          = "ashes-org-log-archive"
}

# Feed known vpc ids + subnet tiers so downstream for_each keys are plan-known.
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
  }
}

# Known TGW outputs so the route-table-per-segment assertion is non-vacuous.
override_module {
  target = module.transit_gateway
  outputs = {
    tgw_id = "tgw-000000000000abcd"
    route_table_ids = {
      prod       = "tgw-rtb-prod00000000"
      nonprod    = "tgw-rtb-nonprod00000"
      inspection = "tgw-rtb-inspection00"
      shared     = "tgw-rtb-shared000000"
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

override_module { target = module.network_firewall }
override_module { target = module.network_access_analyzer }

run "composes_network_hub" {
  command = apply

  # The TGW carries all four segment route tables, including prod & nonprod
  # (where the centralized-inspection default routes live).
  assert {
    condition = alltrue([
      for seg in ["prod", "nonprod", "inspection", "shared"] :
      contains(keys(module.transit_gateway.route_table_ids), seg)
    ])
    error_message = "transit gateway must expose prod, nonprod, inspection and shared route tables"
  }

  # Centralized-inspection routing edge (Epic D): the stage must send BOTH the
  # prod and nonprod default routes (0.0.0.0/0) to the inspection attachment so
  # all egress/east-west traffic is forced through the firewall. Non-vacuous:
  # asserts on the concrete route_table/cidr/attachment the stage builds and
  # feeds to module.transit_gateway (surfaced via the tgw_inspection_routes
  # output because the TGW child is override_module'd).
  assert {
    condition = alltrue([
      for seg in ["prod", "nonprod"] :
      output.tgw_inspection_routes["${seg}:default"].route_table == seg &&
      output.tgw_inspection_routes["${seg}:default"].cidr == "0.0.0.0/0" &&
      output.tgw_inspection_routes["${seg}:default"].attachment == "inspection"
    ])
    error_message = "stage must route prod and nonprod default (0.0.0.0/0) traffic to the inspection attachment"
  }

  # And it must build exactly those two default routes - no segment missing.
  assert {
    condition = length(keys(output.tgw_inspection_routes)) == 2 && alltrue([
      for k in ["prod:default", "nonprod:default"] : contains(keys(output.tgw_inspection_routes), k)
    ])
    error_message = "stage must construct exactly the prod:default and nonprod:default inspection routes"
  }

  # tgw_id surfaces through the stage output (routing contract wiring proof).
  assert {
    condition     = output.tgw_id == "tgw-000000000000abcd"
    error_message = "tgw_id output must surface module.transit_gateway.tgw_id"
  }

  # egress_vpc_id wires through from the (overridden) vpc child.
  assert {
    condition     = output.egress_vpc_id == "vpc-egress0000000001"
    error_message = "egress_vpc_id output must surface module.egress_vpc.vpc_id"
  }

  # inspection_vpc_id wires through from the (overridden) vpc child.
  assert {
    condition     = output.inspection_vpc_id == "vpc-inspection000001"
    error_message = "inspection_vpc_id output must surface module.inspection_vpc.vpc_id"
  }

  # IPAM regional pool ids surface as the app-root allocation contract.
  assert {
    condition     = output.ipam_pool_ids["eu-west-2"] == "ipam-pool-eu-west-2-0"
    error_message = "ipam_pool_ids output must surface module.ipam.regional_pool_ids"
  }

  # Resolver Profile id surfaces for org-wide DNS distribution.
  assert {
    condition     = output.resolver_profile_id == "rp-0000000000000000"
    error_message = "resolver_profile_id output must surface module.route53_resolver.resolver_profile_id"
  }

  # Private hosted zone id fronting the interface endpoints surfaces.
  assert {
    condition     = output.interface_endpoint_phz_id == "Z0000000000000000000"
    error_message = "interface_endpoint_phz_id output must surface module.vpc_endpoints.phz_id"
  }

  # Stage-level NAT: one NAT gateway per egress public subnet (two here).
  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "stage must create one NAT gateway per egress public subnet"
  }

  # The egress private route table default route egresses via a NAT gateway.
  assert {
    condition     = aws_route.egress_default.destination_cidr_block == "0.0.0.0/0"
    error_message = "egress private default route must be 0.0.0.0/0 via NAT"
  }
}
