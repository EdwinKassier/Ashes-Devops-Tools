# Resource-assertion tests for the network/packet-mirroring module.
# Prior tests only validated inputs; nothing asserted that the filter and
# mirrored-source inputs actually map onto the resource (audit round-3 §D8 /
# finding #10). The filter block and mirrored_resources are config-derived and
# therefore plan-knowable under mock_provider.

mock_provider "google" {}

variables {
  project_id        = "mock-project"
  name              = "test-mirroring"
  region            = "us-central1"
  network           = "projects/mock-project/global/networks/mock-vpc"
  collector_ilb_url = "projects/mock-project/regions/us-central1/forwardingRules/mock-ilb"
  mirrored_subnetworks = [
    "projects/mock-project/regions/us-central1/subnetworks/mock-subnet",
  ]
}

run "filter_and_sources_map_onto_the_resource" {
  command = plan

  variables {
    filter_direction    = "INGRESS"
    filter_ip_protocols = ["tcp"]
    filter_cidr_ranges  = ["10.0.0.0/8"]
  }

  assert {
    condition     = google_compute_packet_mirroring.mirroring[0].filter[0].direction == "INGRESS"
    error_message = "filter.direction must map from var.filter_direction."
  }
  assert {
    condition     = contains(google_compute_packet_mirroring.mirroring[0].filter[0].ip_protocols, "tcp")
    error_message = "filter.ip_protocols must map from var.filter_ip_protocols."
  }
  assert {
    condition     = contains(google_compute_packet_mirroring.mirroring[0].filter[0].cidr_ranges, "10.0.0.0/8")
    error_message = "filter.cidr_ranges must map from var.filter_cidr_ranges."
  }
  assert {
    condition     = length(google_compute_packet_mirroring.mirroring[0].mirrored_resources[0].subnetworks) == 1
    error_message = "One mirrored subnetwork must be wired per var.mirrored_subnetworks entry."
  }
}
