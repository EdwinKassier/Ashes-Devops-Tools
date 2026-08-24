# Variable validation tests for the network/vpn module (mock_provider — no creds).

mock_provider "aws" {}

variables {
  name                = "onprem-dc1"
  customer_gateway_ip = "203.0.113.10"
  transit_gateway_id  = "tgw-0123456789abcdef0"
}

run "accepts_valid_tgw_defaults" {
  command = plan
}

run "rejects_bad_customer_gateway_ip" {
  command = plan

  expect_failures = [var.customer_gateway_ip]

  variables {
    customer_gateway_ip = "not-an-ip"
  }
}

run "rejects_bad_attach_to" {
  command = plan

  expect_failures = [var.attach_to]

  variables {
    attach_to = "direct_connect"
  }
}

run "rejects_odd_tunnel_cidr_count" {
  command = plan

  expect_failures = [var.tunnel_inside_cidrs]

  variables {
    tunnel_inside_cidrs = ["169.254.10.0/30"]
  }
}

run "rejects_bad_name" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "bad name!"
  }
}
