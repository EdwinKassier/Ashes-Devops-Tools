# Variable validation tests for the gke-autopilot module.
# All runs use mock_provider so no GCP credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "mock-cluster"
  location   = "europe-west1"
  network    = "projects/mock-project/global/networks/hub"
  subnetwork = "projects/mock-project/regions/europe-west1/subnetworks/apps"
}

# ── project_id ─────────────────────────────────────────────────────────────────

run "accepts_valid_project_id" {
  command = plan

  variables {
    project_id = "valid-project-123"
  }
}

run "rejects_invalid_project_id" {
  command = plan

  expect_failures = [var.project_id]

  variables {
    project_id = "INVALID PROJECT!"
  }
}

# ── name ───────────────────────────────────────────────────────────────────────

run "rejects_invalid_cluster_name" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "Invalid_Name"
  }
}

# ── location ───────────────────────────────────────────────────────────────────

run "rejects_invalid_location" {
  command = plan

  expect_failures = [var.location]

  variables {
    location = "not a region"
  }
}

# ── release_channel ────────────────────────────────────────────────────────────

run "accepts_stable_release_channel" {
  command = plan

  variables {
    release_channel = "STABLE"
  }
}

run "rejects_invalid_release_channel" {
  command = plan

  expect_failures = [var.release_channel]

  variables {
    release_channel = "NIGHTLY"
  }
}

# ── master_ipv4_cidr_block ─────────────────────────────────────────────────────

run "rejects_invalid_master_cidr" {
  command = plan

  expect_failures = [var.master_ipv4_cidr_block]

  variables {
    master_ipv4_cidr_block = "not-a-cidr"
  }
}

# ── master_authorized_networks (cross-variable guard) ──────────────────────────

run "accepts_private_endpoint_with_no_authorized_networks" {
  command = plan

  variables {
    enable_private_endpoint    = true
    master_authorized_networks = []
  }
}

run "rejects_public_endpoint_without_authorized_networks" {
  command = plan

  expect_failures = [var.master_authorized_networks]

  variables {
    enable_private_endpoint    = false
    master_authorized_networks = []
  }
}
