# The stage hands pool growth and the RAM share scope to the real ipam module.
# Unlike the other suites this one does not stub module.ipam, so the assertions
# read what the module received.

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

run "pool_growth_and_share_scope_reach_the_ipam_module" {
  command = plan

  variables {
    top_cidr                  = "10.0.0.0/8"
    regional_additional_cidrs = { eu-west-2 = ["10.80.0.0/12"] }
    share_principal_arns      = ["arn:aws:organizations::111111111111:ou/o-abc1234567/ou-ab12-workload1"]
  }

  assert {
    condition     = join(",", module.ipam.regional_pool_cidrs["eu-west-2"]) == "10.0.0.0/12,10.80.0.0/12"
    error_message = "regional_additional_cidrs must reach the ipam module."
  }

  assert {
    condition     = join(",", module.ipam.share_principals) == "arn:aws:organizations::111111111111:ou/o-abc1234567/ou-ab12-workload1"
    error_message = "share_principal_arns must replace the org-wide share principal."
  }
}

run "defaults_share_the_whole_organization" {
  command = plan

  assert {
    condition     = join(",", module.ipam.share_principals) == var.org_arn && join(",", module.ipam.regional_pool_cidrs["eu-west-2"]) == "10.0.0.0/12"
    error_message = "With no share_principal_arns the pools are shared with the organization, and no extra CIDR is provisioned."
  }
}
