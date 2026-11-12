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

# The alarm actions validate the topic ARN, which a mock would generate as random text.
mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:eu-west-2:111111111111:network-hub-alarms" }
  }
}

variables {
  org_id                   = "o-abc1234567"
  org_arn                  = "arn:aws:organizations::111111111111:organization/o-abc1234567"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_bucket_name          = "ashes-org-log-archive"
  alarm_subscriber_emails  = ["netops@corp.test"]
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
  target = module.vpc_endpoints
  outputs = {
    phz_id               = "Z0000000000000000000"
    shared_dns_zone_arns = { ssm = "arn:aws:route53:::hostedzone/Z0000000000000000001" }
  }
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

  # Centralized inspection inside the inspection VPC: each AZ's tgw-tier table
  # must send 0.0.0.0/0 to the SAME-AZ firewall endpoint (symmetric routing).
  assert {
    condition = (
      aws_route.inspection_tgw_to_firewall["0"].route_table_id == "rtb-insp-tgw-a" &&
      aws_route.inspection_tgw_to_firewall["0"].vpc_endpoint_id == "vpce-fw-a" &&
      aws_route.inspection_tgw_to_firewall["1"].route_table_id == "rtb-insp-tgw-b" &&
      aws_route.inspection_tgw_to_firewall["1"].vpc_endpoint_id == "vpce-fw-b" &&
      aws_route.inspection_tgw_to_firewall["0"].destination_cidr_block == "0.0.0.0/0"
    )
    error_message = "inspection tgw tier must default-route to the same-AZ Network Firewall endpoint"
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

  # Per-AZ HA egress: one default route per AZ, each written into the
  # vpc-module-owned private route table of the SAME AZ (no stage-owned tables).
  assert {
    condition     = length(aws_route.egress_default) == 2
    error_message = "stage must create one egress private default route per AZ"
  }

  assert {
    condition = (
      aws_route.egress_default["0"].route_table_id == "rtb-egr-prv-a" &&
      aws_route.egress_default["1"].route_table_id == "rtb-egr-prv-b"
    )
    error_message = "each AZ's NAT default route must target the module-owned private route table of the same AZ"
  }

  assert {
    condition     = alltrue([for r in values(aws_route.egress_default) : r.destination_cidr_block == "0.0.0.0/0"])
    error_message = "each AZ's egress default route must be 0.0.0.0/0 via NAT"
  }

  # Spoke traffic arriving on the egress tgw tier leaves via the same-AZ NAT.
  assert {
    condition = (
      length(aws_route.egress_tgw_default) == 2 &&
      aws_route.egress_tgw_default["1"].route_table_id == "rtb-egr-tgw-b" &&
      aws_route.egress_tgw_default["1"].destination_cidr_block == "0.0.0.0/0"
    )
    error_message = "egress tgw-tier route tables must default-route to the same-AZ NAT gateway"
  }

  # Return / hand-off routes to the TGW: egress public + private -> top_cidr,
  # inspection firewall -> 0.0.0.0/0 (2 AZs x 3 tables).
  assert {
    condition     = length(aws_route.hub_to_tgw) == 6
    error_message = "stage must create TGW routes for egress public/private and inspection firewall tables in every AZ"
  }

  assert {
    condition = alltrue([
      for r in values(aws_route.hub_to_tgw) : r.transit_gateway_id == "tgw-000000000000abcd"
    ])
    error_message = "hub TGW routes must target the hub transit gateway"
  }

  assert {
    condition = (
      aws_route.hub_to_tgw["egress-private-0"].destination_cidr_block == var.top_cidr &&
      aws_route.hub_to_tgw["egress-private-0"].route_table_id == "rtb-egr-prv-a" &&
      aws_route.hub_to_tgw["inspection-firewall-1"].destination_cidr_block == "0.0.0.0/0" &&
      aws_route.hub_to_tgw["inspection-firewall-1"].route_table_id == "rtb-insp-fw-b"
    )
    error_message = "egress return routes must cover top_cidr and the inspection firewall tier must default-route to the TGW"
  }

  # Route tables are surfaced from the vpc module, not rebuilt by the stage.
  assert {
    condition     = output.egress_route_table_ids_by_tier["private"][0] == "rtb-egr-prv-a"
    error_message = "egress_route_table_ids_by_tier must surface module.egress_vpc.route_table_ids_by_tier"
  }
}

# Adding ipv4_ipam_pool_id to an existing static VPC forces replacement, so by
# default (ipam_mode_for_new_vpcs_only = true, ipam_new_vpcs = []) no hub VPC is
# moved to the pool.
run "existing_vpc_not_moved_to_pool" {
  command = plan

  assert {
    condition     = local.hub_vpc_ipam_pool_ids == { inspection = "", egress = "" }
    error_message = "with defaults no hub VPC may receive an IPAM pool"
  }
}

run "only_listed_new_vpcs_use_the_pool" {
  command = plan

  variables {
    ipam_new_vpcs = ["egress"]
  }

  assert {
    condition     = local.hub_vpc_ipam_pool_ids == { inspection = "", egress = "ipam-pool-eu-west-2-0" }
    error_message = "only the VPC named in ipam_new_vpcs gets the regional pool; the other keeps static attributes"
  }
}

run "all_hub_vpcs_use_pool_when_new_only_disabled" {
  command = plan

  variables {
    ipam_mode_for_new_vpcs_only = false
  }

  assert {
    condition     = local.hub_vpc_ipam_pool_ids == { inspection = "ipam-pool-eu-west-2-0", egress = "ipam-pool-eu-west-2-0" }
    error_message = "disabling the new-only gate moves both hub VPCs to the pool"
  }
}

# A static hub VPC is not an IPAM allocation, so without a manual allocation the
# regional pool could hand its range to a spoke. Each static hub VPC inside the
# home-region pool is reserved there.
run "static_hub_vpcs_are_reserved_in_the_pool" {
  command = plan

  assert {
    condition = (
      length(aws_vpc_ipam_pool_cidr_allocation.hub_static) == 2 &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["inspection"].cidr == var.inspection_cidr &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["egress"].cidr == var.egress_cidr &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["inspection"].ipam_pool_id == "ipam-pool-eu-west-2-0" &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["egress"].ipam_pool_id == "ipam-pool-eu-west-2-0"
    )
    error_message = "Static hub VPCs must hold a manual allocation in the regional pool so IPAM never hands their range to a spoke."
  }

  assert {
    condition     = output.hub_static_ipam_allocations == { inspection = var.inspection_cidr, egress = var.egress_cidr }
    error_message = "hub_static_ipam_allocations must map each reserved hub VPC to its CIDR."
  }
}

run "pool_allocated_hub_vpc_needs_no_reservation" {
  command = plan

  variables {
    ipam_new_vpcs = ["egress"]
  }

  assert {
    condition     = keys(aws_vpc_ipam_pool_cidr_allocation.hub_static) == ["inspection"]
    error_message = "A hub VPC that allocates from the pool is its own allocation; only static hubs are reserved."
  }
}

run "no_reservation_when_both_hub_vpcs_use_the_pool" {
  command = plan

  variables {
    ipam_mode_for_new_vpcs_only = false
  }

  assert {
    condition     = length(aws_vpc_ipam_pool_cidr_allocation.hub_static) == 0
    error_message = "With ipam_mode_for_new_vpcs_only = false both hub VPCs allocate from the pool, so nothing is reserved."
  }
}

# A hub VPC outside the home-region pool cannot be handed to a spoke from that
# pool, and IPAM rejects an allocation outside the pool CIDR.
run "hub_vpc_outside_the_regional_pool_is_not_reserved" {
  command = plan

  variables {
    egress_cidr = "10.32.0.0/16"
  }

  assert {
    condition     = keys(aws_vpc_ipam_pool_cidr_allocation.hub_static) == ["inspection"]
    error_message = "Only hub VPCs inside the regional pool CIDR are reserved there."
  }
}

# A hub VPC that only partly overlaps the regional pool cannot be reserved, and
# a spoke can still get part of its range: fail the plan.
run "hub_vpc_straddling_the_regional_pool_fails" {
  command = plan

  variables {
    inspection_cidr = "10.0.0.0/11"
  }

  expect_failures = [aws_vpc_ipam_pool_cidr_allocation.hub_static["inspection"]]
}

# The home-region pool can hold extra CIDRs (regional_additional_cidrs). A static
# hub VPC inside one of them is reserved there too, or IPAM could hand its range
# to a spoke.
run "static_hub_vpc_in_an_additional_pool_cidr_is_reserved" {
  command = plan

  variables {
    top_cidr                  = "10.0.0.0/8"
    regional_additional_cidrs = { eu-west-2 = ["10.80.0.0/12"] }
    egress_cidr               = "10.80.0.0/16"
  }

  assert {
    condition = (
      keys(aws_vpc_ipam_pool_cidr_allocation.hub_static) == ["egress", "inspection"] &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["egress"].cidr == "10.80.0.0/16" &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["egress"].ipam_pool_id == "ipam-pool-eu-west-2-0"
    )
    error_message = "A static hub VPC inside an additional home-region pool CIDR must be reserved in the pool."
  }
}

# Partly overlapping an additional CIDR is the same hazard as partly overlapping
# the first one.
run "hub_vpc_straddling_an_additional_pool_cidr_fails" {
  command = plan

  variables {
    top_cidr                  = "10.0.0.0/8"
    regional_additional_cidrs = { eu-west-2 = ["10.80.0.0/12"] }
    egress_cidr               = "10.64.0.0/10"
  }

  expect_failures = [aws_vpc_ipam_pool_cidr_allocation.hub_static["egress"]]
}

# Additional CIDRs of another region do not hold the home-region hub ranges.
run "additional_cidrs_of_another_region_do_not_reserve_hub_vpcs" {
  command = plan

  variables {
    aws_enabled_regions       = ["eu-west-2", "eu-west-1"]
    top_cidr                  = "10.0.0.0/8"
    regional_additional_cidrs = { eu-west-1 = ["10.80.0.0/12"] }
    egress_cidr               = "10.80.0.0/16"
  }

  assert {
    condition     = keys(aws_vpc_ipam_pool_cidr_allocation.hub_static) == ["inspection"]
    error_message = "Only the home-region pool CIDRs decide which hub VPCs are reserved."
  }
}

run "interface_endpoints_admit_the_org_supernet" {
  command = plan

  variables {
    top_cidr = "10.64.0.0/10"
  }

  assert {
    condition     = length(local.endpoint_allowed_cidrs) == 1 && local.endpoint_allowed_cidrs[0] == "10.64.0.0/10"
    error_message = "The central interface endpoints must admit HTTPS from top_cidr, so the spokes can reach them (the VPC default security group denies everything)."
  }
}

run "hub_network_alarms_exist" {
  command = apply

  # tgw_id is known (override_module), the NAT ids are mock values: assert the
  # metric identity, which is what makes an alarm real or silently empty.
  assert {
    condition = (
      output.network_alarms["tgw-blackhole-drops"].namespace == "AWS/TransitGateway" &&
      output.network_alarms["tgw-blackhole-drops"].metric_name == "PacketDropCountBlackhole" &&
      output.network_alarms["tgw-blackhole-drops"].dimensions == { TransitGateway = "tgw-000000000000abcd" }
    )
    error_message = "the hub must alarm on blackhole drops of its own transit gateway"
  }

  assert {
    condition     = toset(keys(output.network_alarms)) == toset(["nat-port-allocation-errors-0", "nat-port-allocation-errors-1", "tgw-blackhole-drops"])
    error_message = "one NAT alarm per AZ, the blackhole alarm, and no VPN alarm without enable_vpn"
  }

  assert {
    condition = alltrue([
      for k in ["nat-port-allocation-errors-0", "nat-port-allocation-errors-1"] :
      output.network_alarms[k].namespace == "AWS/NATGateway" &&
      output.network_alarms[k].metric_name == "ErrorPortAllocation" &&
      output.network_alarms[k].statistic == "Sum" &&
      toset(keys(output.network_alarms[k].dimensions)) == toset(["NatGatewayId"])
    ])
    error_message = "the hub must alarm on port allocation errors of every NAT gateway"
  }

  assert {
    condition     = length(module.network_alarms.alarm_arns) == 3 && output.alarm_topic_arn != null
    error_message = "every alarm definition must become an alarm, publishing to a topic"
  }
}

run "alarm_topic_is_created_and_subscribed" {
  command = apply

  variables {
    alarm_subscriber_emails = ["netops@corp.test"]
  }

  assert {
    condition     = length(aws_sns_topic_subscription.alarm_email) == 1 && aws_sns_topic_subscription.alarm_email["netops@corp.test"].protocol == "email"
    error_message = "the topic the stage creates must carry the email subscribers"
  }
}

run "supplied_alarm_topic_is_reused" {
  command = apply

  variables {
    alarm_sns_topic_arn     = "arn:aws:sns:eu-west-2:111111111111:ops-alerts"
    alarm_subscriber_emails = ["netops@corp.test"]
  }

  assert {
    condition     = output.alarm_topic_arn == "arn:aws:sns:eu-west-2:111111111111:ops-alerts" && length(aws_sns_topic_subscription.alarm_email) == 0
    error_message = "a supplied topic is used as is: the stage creates no topic and no subscription"
  }
}
