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

override_module {
  target = module.vpn
  outputs = {
    vpn_connection_id             = "vpn-0123456789abcdef0"
    customer_gateway_id           = "cgw-0123456789abcdef0"
    tunnel1_address               = "198.51.100.10"
    tunnel2_address               = "198.51.100.11"
    transit_gateway_attachment_id = "tgw-attach-vpn0000000"
  }
}

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

  assert {
    condition     = length(module.vpn) == 1 && output.vpn_connection_id == "vpn-0123456789abcdef0" && length(output.vpn_tunnel_addresses) == 2
    error_message = "enable_vpn must plan the Site-to-Site VPN and expose its connection id and tunnel addresses."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.vpn[0].transit_gateway_attachment_id == "tgw-attach-vpn0000000" && aws_ec2_transit_gateway_route_table_association.vpn[0].transit_gateway_route_table_id == "tgw-rtb-shared000000"
    error_message = "The VPN attachment must be associated with the shared TGW route table by default."
  }

  assert {
    condition     = join(",", sort(keys(aws_ec2_transit_gateway_route_table_propagation.vpn))) == "nonprod,prod"
    error_message = "On-premises routes must propagate into prod and nonprod by default."
  }
}

run "vpn_segments_are_configurable" {
  command = apply

  variables {
    enable_vpn = true
    vpn = {
      customer_gateway_ip = "203.0.113.10"
      route_table         = "prod"
      propagate_to        = ["shared"]
    }
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.vpn[0].transit_gateway_route_table_id == "tgw-rtb-prod00000000" && join(",", keys(aws_ec2_transit_gateway_route_table_propagation.vpn)) == "shared"
    error_message = "vpn.route_table and vpn.propagate_to must select the TGW segments."
  }
}
