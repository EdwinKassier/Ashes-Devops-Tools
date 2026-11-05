# Plan assertions for the gke-autopilot module: verify the google_container_cluster
# is planned in Autopilot mode, wired to the caller-supplied identity/network, and
# hardened by default (private nodes + private endpoint, Workload Identity, Gateway API).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "mock-cluster"
  location   = "europe-west1"
  network    = "projects/mock-project/global/networks/hub"
  subnetwork = "projects/mock-project/regions/europe-west1/subnetworks/apps"
}

run "cluster_is_autopilot_and_wired" {
  command = plan

  assert {
    condition     = google_container_cluster.this.enable_autopilot == true
    error_message = "Cluster must be created in Autopilot mode."
  }

  assert {
    condition     = google_container_cluster.this.name == var.name
    error_message = "Cluster name must be the caller-supplied name."
  }

  assert {
    condition     = google_container_cluster.this.location == var.location
    error_message = "Cluster must be created in the caller-supplied location."
  }

  assert {
    condition     = google_container_cluster.this.network == var.network
    error_message = "Cluster must attach to the caller-supplied Shared VPC network."
  }

  assert {
    condition     = google_container_cluster.this.subnetwork == var.subnetwork
    error_message = "Cluster must attach to the caller-supplied Shared VPC subnetwork."
  }
}

run "cluster_is_private_and_hardened_by_default" {
  command = plan

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_nodes == true
    error_message = "Nodes must be private."
  }

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_endpoint == true
    error_message = "Control-plane endpoint must be private by default."
  }

  assert {
    condition     = google_container_cluster.this.deletion_protection == true
    error_message = "deletion_protection must be on by default."
  }

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 1
    error_message = "Deletion-protection guard must be created by default."
  }

  assert {
    condition     = google_container_cluster.this.release_channel[0].channel == "REGULAR"
    error_message = "release_channel must default to REGULAR."
  }

  assert {
    condition     = google_container_cluster.this.gateway_api_config[0].channel == "CHANNEL_STANDARD"
    error_message = "Gateway API must be enabled on the standard channel."
  }

  assert {
    condition     = google_container_cluster.this.workload_identity_config[0].workload_pool == "mock-project.svc.id.goog"
    error_message = "Workload Identity pool must be <project>.svc.id.goog."
  }

  assert {
    condition     = output.workload_pool == "mock-project.svc.id.goog"
    error_message = "workload_pool output must surface <project>.svc.id.goog."
  }
}

run "public_endpoint_with_authorized_networks" {
  command = plan

  variables {
    enable_private_endpoint = false
    master_authorized_networks = [
      { cidr_block = "10.0.0.0/8", display_name = "corp" },
    ]
  }

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_endpoint == false
    error_message = "enable_private_endpoint must reflect the input variable."
  }

  assert {
    condition     = google_container_cluster.this.master_authorized_networks_config[0].cidr_blocks[0].cidr_block == "10.0.0.0/8"
    error_message = "Authorized network CIDR must be wired into master_authorized_networks_config."
  }
}
