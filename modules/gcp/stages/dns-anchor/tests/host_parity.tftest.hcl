# Migration parity: stages/host (as modules/gcp/stages/network-hub called it
# for the DNS hub, with NAT / Cloud Armor / PSC / PSA off) -> stages/dns-anchor.
# Mock providers cannot prove a `moved` block; identical plan-known names,
# CIDRs and settings mean the moved objects plan with no in-place diff.

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
    project_id                     = "mock-dns-project"
    project_prefix                 = "mock"
    region                         = "us-central1"
    enable_networking              = true
    enable_shared_vpc_host         = false
    enable_cloud_nat               = false
    enable_cloud_armor             = false
    enable_private_service_connect = false
    enable_private_service_access  = false
    vpc_name                       = "dns-vpc-core"
    vpc_cidr_block                 = "10.1.0.0/16"
  }
}

run "dns_anchor_matches_host" {
  command = plan

  variables {
    project_id = "mock-dns-project"
    region     = "us-central1"
    network = {
      name       = "dns-vpc-core"
      cidr_block = "10.1.0.0/16"
    }
  }

  assert {
    condition = alltrue([
      for tier in ["public", "private", "database"] :
      { for z, s in output.subnets[tier] : z => [s.name, s.ip_cidr_range, s.subnet.private_ip_google_access, s.subnet.log_config[0].flow_sampling] } ==
      { for z, s in run.host_baseline.subnets[tier] : z => [s.name, s.ip_cidr_range, s.subnet.private_ip_google_access, s.subnet.log_config[0].flow_sampling] }
    ])
    error_message = "Every DNS-anchor subnet must keep the stages/host name, CIDR and settings."
  }

  assert {
    condition     = output.network_name == run.host_baseline.network_name
    error_message = "The anchor VPC must keep its stages/host name."
  }
}
