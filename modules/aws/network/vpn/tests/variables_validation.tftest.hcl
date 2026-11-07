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

run "rejects_private_customer_gateway_ip" {
  command = plan

  variables {
    customer_gateway_ip = "192.168.1.1"
  }

  expect_failures = [var.customer_gateway_ip]
}

run "rejects_out_of_range_bgp_asn" {
  command = plan

  variables {
    customer_gateway_bgp_asn = 0
  }

  expect_failures = [var.customer_gateway_bgp_asn]
}

run "rejects_unknown_preshared_key_storage" {
  command = plan

  variables {
    preshared_key_storage = "Vault"
  }

  expect_failures = [var.preshared_key_storage]
}
