# Plan assertions for the vpc module: verify secure-by-default network settings,
# the conditional Shared VPC host / deletion-protection guard resources, and that
# overrides change behaviour. All runs use mock_provider (no GCP credentials).

mock_provider "google" {}

variables {
  project_id = "mock-project"
  vpc_name   = "mock-vpc"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = google_compute_network.vpc.name == "mock-vpc" && google_compute_network.vpc.project == "mock-project"
    error_message = "Network must be created with the caller-supplied name in the caller-supplied project."
  }

  assert {
    condition     = google_compute_network.vpc.auto_create_subnetworks == false
    error_message = "Network must default to custom subnet mode (auto_create_subnetworks = false)."
  }

  assert {
    condition     = google_compute_network.vpc.delete_default_routes_on_create == true
    error_message = "Default 0.0.0.0/0 internet route must be deleted on create by default (no implicit egress)."
  }

  assert {
    condition     = google_compute_network.vpc.routing_mode == "GLOBAL"
    error_message = "routing_mode must default to GLOBAL."
  }

  assert {
    condition     = google_compute_network.vpc.description == "Managed by Terraform"
    error_message = "description must default to 'Managed by Terraform'."
  }

  assert {
    condition     = length(google_compute_shared_vpc_host_project.host) == 0
    error_message = "Shared VPC host project must not be enabled by default."
  }

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 0
    error_message = "Deletion-protection guard must be absent by default."
  }
}

run "shared_vpc_host_and_guard_enabled" {
  command = plan

  variables {
    enable_shared_vpc_host     = true
    enable_deletion_protection = true
  }

  assert {
    condition     = length(google_compute_shared_vpc_host_project.host) == 1
    error_message = "enable_shared_vpc_host = true must create exactly one Shared VPC host project resource."
  }

  assert {
    condition     = google_compute_shared_vpc_host_project.host[0].project == "mock-project"
    error_message = "Shared VPC host must be enabled on the network's own project."
  }

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 1
    error_message = "enable_deletion_protection = true must create the prevent_destroy guard."
  }

  assert {
    condition     = terraform_data.deletion_protection_guard[0].input == "mock-vpc"
    error_message = "Deletion-protection guard must be keyed to the VPC name."
  }
}

run "overrides_change_behaviour" {
  command = plan

  variables {
    routing_mode                    = "REGIONAL"
    delete_default_routes_on_create = false
  }

  assert {
    condition     = google_compute_network.vpc.routing_mode == "REGIONAL"
    error_message = "routing_mode override must be honoured."
  }

  assert {
    condition     = google_compute_network.vpc.delete_default_routes_on_create == false
    error_message = "delete_default_routes_on_create override must be honoured."
  }
}
