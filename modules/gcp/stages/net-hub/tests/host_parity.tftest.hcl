# Migration parity: stages/host (as modules/gcp/stages/network-hub called it
# for the hub VPC) -> stages/net-hub. Mock providers cannot prove a `moved`
# block; identical plan-known names, CIDRs and settings mean the moved objects
# plan with no in-place diff.

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a", "us-central1-b", "us-central1-c"]
    }
  }
}
mock_provider "google-beta" {}

run "host_baseline" {
  command = plan

  module {
    source = "../host"
  }

  variables {
    project_id                      = "mock-hub-project"
    project_prefix                  = "mock"
    region                          = "us-central1"
    enable_networking               = true
    enable_shared_vpc_host          = true
    vpc_name                        = "hub-vpc-core"
    vpc_cidr_block                  = "10.0.0.0/16"
    log_config_flow_sampling        = 0.5
    log_config_aggregation_interval = "INTERVAL_5_SEC"
  }
}

run "net_hub_matches_host" {
  command = plan

  variables {
    project_id     = "mock-hub-project"
    project_prefix = "mock"
    region         = "us-central1"
    network = {
      name            = "hub-vpc-core"
      cidr_block      = "10.0.0.0/16"
      shared_vpc_host = true
      flow_logs       = { aggregation_interval = "INTERVAL_5_SEC", sampling = 0.5 }
    }
  }

  assert {
    condition = alltrue([
      for tier in ["public", "private", "database"] :
      { for z, s in output.subnets[tier] : z => [s.name, s.ip_cidr_range, s.subnet.private_ip_google_access, s.subnet.log_config[0].flow_sampling] } ==
      { for z, s in run.host_baseline.subnets[tier] : z => [s.name, s.ip_cidr_range, s.subnet.private_ip_google_access, s.subnet.log_config[0].flow_sampling] }
    ])
    error_message = "Every hub subnet must keep the stages/host name, CIDR and settings."
  }

  assert {
    condition     = output.network_name == run.host_baseline.network_name && output.private_service_access_range_name == run.host_baseline.private_service_access_range_name && output.network_tags == run.host_baseline.network_tags
    error_message = "VPC name, PSA range and network tags must match stages/host."
  }

  assert {
    condition     = length([output.network_self_link, output.network_name, output.subnets, output.nat_ip]) == 4
    error_message = "net-hub must expose every output the network-hub stage reads."
  }
}
