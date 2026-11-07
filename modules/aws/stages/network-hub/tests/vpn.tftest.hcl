# Opt-in Site-to-Site VPN on the transit gateway: off by default, and when on it
# terminates on the hub TGW and is associated with / propagated into the
# configured segments. Same stubbing as plan_assertions.tftest.hcl.

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

run "vpn_off_by_default" {
  command = apply

  assert {
    condition     = length(module.vpn) == 0 && length(aws_ec2_transit_gateway_route_table_association.vpn) == 0 && length(aws_ec2_transit_gateway_route_table_propagation.vpn) == 0 && output.vpn_connection_id == null && length(output.vpn_tunnel_addresses) == 0
    error_message = "enable_vpn defaults to false: no VPN, association or propagation, null VPN outputs."
  }
}

run "aws_vpn_attaches_to_tgw" {
  command = apply

  variables {
    enable_vpn = true
    vpn        = { customer_gateway_ip = "203.0.113.10" }
  }

  # module.vpn is planned for real (not overridden): the stage hands it the hub
  # TGW id; the module's own suite asserts attach_to = transit_gateway.
  assert {
    condition     = length(module.vpn) == 1 && length(output.vpn_tunnel_addresses) == 2
    error_message = "enable_vpn must plan the Site-to-Site VPN and expose its tunnel addresses."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.vpn[0].transit_gateway_route_table_id == "tgw-rtb-hybrid000000"
    error_message = "The VPN attachment must be associated with the dedicated hybrid TGW route table."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_propagation.vpn[0].transit_gateway_route_table_id == "tgw-rtb-inspection00"
    error_message = "On-premises routes must propagate into the inspection route table only (never prod or nonprod)."
  }

  assert {
    condition     = output.tgw_inspection_routes["hybrid:default"].attachment == "inspection" && output.tgw_inspection_routes["hybrid:default"].cidr == "0.0.0.0/0" && output.tgw_inspection_routes["hybrid:default"].route_table == "hybrid"
    error_message = "The hybrid route table must default-route to the inspection attachment."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.vpn_onprem) == 0
    error_message = "BGP routing creates no static on-premises routes."
  }
}

run "static_routing_pins_onprem_cidrs_to_the_vpn" {
  command = apply

  variables {
    enable_vpn = true
    vpn = {
      customer_gateway_ip = "203.0.113.10"
      static_routes_only  = true
      onprem_cidrs        = ["192.168.0.0/16", "172.20.0.0/14"]
    }
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.vpn_onprem) == 2 && alltrue([for r in aws_ec2_transit_gateway_route.vpn_onprem : r.transit_gateway_route_table_id == "tgw-rtb-inspection00"])
    error_message = "Static on-premises prefixes must be routes in the inspection route table."
  }
}

run "spoke_routes_stay_default_to_inspection" {
  command = apply

  variables {
    enable_vpn = true
    vpn        = { customer_gateway_ip = "203.0.113.10" }
  }

  assert {
    condition     = output.tgw_inspection_routes["prod:default"].attachment == "inspection" && output.tgw_inspection_routes["nonprod:default"].attachment == "inspection"
    error_message = "Spoke segments must keep default-routing to inspection so return traffic to on-premises is inspected."
  }
}
