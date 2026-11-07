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

run "production_profile_alert_only_fails" {
  command = plan

  variables {
    enforce_egress_allowlist = true
  }

  expect_failures = [terraform_data.production_egress_enforced]
}

run "production_allowlist_without_drop_fails" {
  command = plan

  variables {
    enforce_egress_allowlist                 = true
    network_firewall_egress_domain_allowlist = [".amazonaws.com"]
  }

  expect_failures = [terraform_data.production_egress_enforced]
}

run "production_drop_without_allowlist_fails" {
  command = plan

  variables {
    enforce_egress_allowlist                  = true
    network_firewall_stateful_default_actions = ["aws:drop_established", "aws:alert_established"]
  }

  expect_failures = [terraform_data.production_egress_enforced]
}

run "production_profile_with_seeded_allowlist_plans" {
  command = plan

  variables {
    enforce_egress_allowlist                  = true
    network_firewall_stateful_default_actions = ["aws:drop_established", "aws:alert_established"]
    network_firewall_egress_domain_allowlist  = [".amazonaws.com", ".github.com", ".githubusercontent.com", ".terraform.io"]
  }
}

run "starter_profile_unaffected" {
  command = plan

  variables {
    enforce_egress_allowlist = false
  }
}

run "waiver_plans" {
  command = plan

  variables {
    enforce_egress_allowlist = true
    egress_alert_only_waived = true
  }
}
