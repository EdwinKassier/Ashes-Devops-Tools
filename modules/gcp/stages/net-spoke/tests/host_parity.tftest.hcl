# Migration parity: stages/host -> stages/net-spoke.
#
# Plans the deprecated stages/host module with the inputs envs/gcp/workload
# used to pass, then plans net-spoke with the equivalent typed inputs, and
# asserts that every output the workload root consumes exists and that the
# known-at-plan attributes of the objects behind the moved addresses are
# identical. Mock providers cannot prove a `moved` block, but identical names,
# CIDRs and settings mean the moved objects plan with no in-place diff.

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c"]
    }
  }
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
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
    project_id                      = "mock-host-project"
    project_prefix                  = "mock-dev"
    region                          = "europe-west1"
    vpc_name                        = "mock-dev-vpc"
    vpc_cidr_block                  = "10.10.0.0/16"
    enable_networking               = true
    enable_shared_vpc_host          = true
    log_config_flow_sampling        = 0.25
    log_config_aggregation_interval = "INTERVAL_1_MIN"
    labels                          = { env = "dev" }
    vpc_peerings = {
      "hub-peering" = { peer_network = "projects/hub/global/networks/hub-vpc-core", export_custom_routes = true, import_custom_routes = true }
    }
    dns_zones = {
      "internal-peering" = {
        dns_name        = "internal.example.com."
        visibility      = "private"
        description     = "Peering zone to resolve internal hub DNS"
        peering_network = "projects/hub/global/networks/hub-vpc-core"
        dnssec_enabled  = true
      }
    }
    enable_vpc_flow_logs_export           = true
    vpc_flow_logs_create_bigquery_dataset = true
    vpc_flow_logs_bigquery_dataset_id     = "vpc_flow_logs_dev"
    vpc_flow_logs_bigquery_location       = "europe-west1"
    vpc_flow_logs_retention_days          = 30
  }
}

run "net_spoke_matches_host" {
  command = plan

  variables {
    project_id     = "mock-host-project"
    project_prefix = "mock-dev"
    region         = "europe-west1"
    labels         = { env = "dev" }
    network = {
      name            = "mock-dev-vpc"
      cidr_block      = "10.10.0.0/16"
      shared_vpc_host = true
      flow_logs       = { aggregation_interval = "INTERVAL_1_MIN", sampling = 0.25 }
    }
    peerings = {
      "hub-peering" = { peer_network = "projects/hub/global/networks/hub-vpc-core", export_custom_routes = true, import_custom_routes = true }
    }
    dns_zones = {
      "internal-peering" = {
        dns_name        = "internal.example.com."
        visibility      = "private"
        description     = "Peering zone to resolve internal hub DNS"
        peering_network = "projects/hub/global/networks/hub-vpc-core"
        dnssec_enabled  = true
      }
    }
    flow_logs_export = {
      enabled                 = true
      create_bigquery_dataset = true
      bigquery_dataset_id     = "vpc_flow_logs_dev"
      bigquery_location       = "europe-west1"
      retention_days          = 30
    }
  }

  # Subnets (moved host.module.<tier>_subnets -> host.module.network.module.<tier>_subnets).
  assert {
    condition = alltrue([
      for tier in ["public", "private", "database"] :
      { for z, s in output.subnets[tier] : z => [s.name, s.ip_cidr_range, s.subnet.private_ip_google_access, s.subnet.log_config[0].flow_sampling, s.subnet.log_config[0].aggregation_interval] } ==
      { for z, s in run.host_baseline.subnets[tier] : z => [s.name, s.ip_cidr_range, s.subnet.private_ip_google_access, s.subnet.log_config[0].flow_sampling, s.subnet.log_config[0].aggregation_interval] }
    ])
    error_message = "Every subnet must keep the stages/host name, CIDR, Private Google Access and flow-log settings."
  }

  # VPC (moved host.module.vpc[0] -> host.module.network.module.vpc).
  assert {
    condition     = output.network_name == run.host_baseline.network_name && output.vpc.network.routing_mode == run.host_baseline.vpc.network.routing_mode && output.vpc.network.delete_default_routes_on_create == run.host_baseline.vpc.network.delete_default_routes_on_create
    error_message = "The VPC must keep its stages/host name and settings."
  }

  # Services that keep their address (no move needed).
  assert {
    condition     = output.private_service_access_range_name == run.host_baseline.private_service_access_range_name && output.network_tags == run.host_baseline.network_tags
    error_message = "PSA range name and network tags must match stages/host."
  }

  assert {
    condition = (
      keys(output.dns_zones) == keys(run.host_baseline.dns_zones) &&
      output.dns_zones["internal-peering"].zone.dns_name == run.host_baseline.dns_zones["internal-peering"].zone.dns_name &&
      output.dns_zones["internal-peering"].zone.description == run.host_baseline.dns_zones["internal-peering"].zone.description &&
      output.dns_zones["internal-peering"].zone.labels == run.host_baseline.dns_zones["internal-peering"].zone.labels
    )
    error_message = "The DNS peering zone must match stages/host."
  }

  assert {
    condition     = keys(output.vpc_peerings) == keys(run.host_baseline.vpc_peerings) && output.vpc_flow_logs_sink_name == run.host_baseline.vpc_flow_logs_sink_name
    error_message = "Peering keys and the flow-log sink must match stages/host."
  }

  # Every module.host output envs/gcp/workload reads still exists on net-spoke
  # (a missing output is a reference error; the list length is plan-known).
  assert {
    condition = length([
      output.network_id, output.network_self_link, output.network_name, output.subnets,
      output.nat_ip, output.dns_zones, output.vpc_peerings, output.security_policy_id,
      output.vpc_service_controls, output.private_service_access_range_name,
    ]) == 10
    error_message = "net-spoke must expose every stages/host output the workload root consumes."
  }
}
