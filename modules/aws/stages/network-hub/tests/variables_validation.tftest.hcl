# Variable-validation tests for the aws-network-hub stage.
#
# A single mock provider. The accept case reaches (and passes) plan with the
# defaults + required vars; the reject case fails the org_arn validation before
# any resource is evaluated.

mock_provider "aws" {}

variables {
  org_id                   = "o-abc1234567"
  org_arn                  = "arn:aws:organizations::111111111111:organization/o-abc1234567"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_bucket_name          = "ashes-org-log-archive"
  alarm_subscriber_emails  = ["netops@corp.test"]
}

run "valid_var_set_accepted" {
  # Accept case: required vars + all defaults must pass validation and plan.
  command = plan
}

run "invalid_org_arn_rejected" {
  # Reject case: a non-Organizations ARN must fail the org_arn validation.
  command = plan

  variables {
    org_arn = "arn:aws:iam::111111111111:role/not-an-org"
  }

  expect_failures = [var.org_arn]
}

run "rejects_enable_vpn_without_customer_gateway_ip" {
  command = plan

  variables {
    enable_vpn = true
  }

  expect_failures = [var.vpn]
}

run "rejects_vpn_asn_equal_to_tgw_asn" {
  command = plan

  variables {
    vpn = { customer_gateway_bgp_asn = 64512 }
  }

  expect_failures = [var.vpn]
}

run "rejects_static_routing_without_onprem_cidrs" {
  command = plan

  variables {
    enable_vpn = true
    vpn        = { customer_gateway_ip = "203.0.113.10", static_routes_only = true }
  }

  expect_failures = [var.vpn]
}

# This file does not override module.vpc_endpoints, so the mode reaches the
# real endpoint policies.
run "resource_org_endpoint_policy_reaches_the_endpoints" {
  command = plan

  variables {
    vpc_endpoint_policy_mode = "org_principals_and_resources"
  }

  assert {
    condition     = join(",", module.vpc_endpoints.resource_org_scoped_services) == "kms"
    error_message = "vpc_endpoint_policy_mode must reach the hub endpoints (kms is the only default service outside the exempt list)."
  }
}

run "endpoint_policy_stays_principal_only_by_default" {
  command = plan

  assert {
    condition     = length(module.vpc_endpoints.resource_org_scoped_services) == 0
    error_message = "The hub endpoint policy must stay aws:PrincipalOrgID only by default."
  }
}

run "rejects_unknown_vpc_endpoint_policy_mode" {
  command = plan

  variables {
    vpc_endpoint_policy_mode = "resources_only"
  }

  expect_failures = [var.vpc_endpoint_policy_mode]
}

run "alarm_subscriber_emails_must_be_addresses" {
  command = plan

  variables {
    alarm_subscriber_emails = ["not-an-address"]
  }

  expect_failures = [var.alarm_subscriber_emails]
}

# Re-audit 5 ARC-2: an extra internal range must be private and outside
# top_cidr, or it passes egress or traffic between segments.
run "internal_pass_cidr_inside_top_cidr_rejected" {
  command = plan

  variables {
    network_firewall_internal_pass_cidrs = ["10.64.0.0/10"]
  }

  expect_failures = [var.network_firewall_internal_pass_cidrs]
}

run "public_internal_pass_cidr_rejected" {
  command = plan

  variables {
    network_firewall_internal_pass_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.network_firewall_internal_pass_cidrs]
}

# Re-audit 5 review: overlapping spoke CIDRs would cross the segment rules.
run "overlapping_spoke_cidrs_rejected" {
  command = plan

  variables {
    spoke_attachments = {
      prod = { attachment_id = "tgw-attach-0123456789abcdef0", segment = "prod", cidr = "10.64.0.0/12" }
      dev  = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod", cidr = "10.70.0.0/16" }
    }
  }

  expect_failures = [var.spoke_attachments]
}

run "spoke_cidr_reusing_a_hub_vpc_rejected" {
  command = plan

  variables {
    spoke_attachments = {
      dev = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod", cidr = "10.1.0.0/16" }
    }
  }

  expect_failures = [var.spoke_attachments]
}

run "spoke_cidr_outside_top_cidr_rejected" {
  command = plan

  variables {
    spoke_attachments = {
      dev = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod", cidr = "172.20.0.0/16" }
    }
  }

  expect_failures = [var.spoke_attachments]
}
