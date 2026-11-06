# Plan assertions for the workload stage after the move from the upstream
# project-factory to the shared project primitive (audit Modularity-H).
# mock_provider only — no GCP credentials required.

mock_provider "google" {}
mock_provider "random" {}

override_resource {
  target = random_id.project_suffix
  values = {
    hex = "1a2b"
  }
}

override_resource {
  target = google_service_account.project
  values = {
    email = "project-service-account@payments-1a2b.iam.gserviceaccount.com"
  }
}

variables {
  project_name               = "payments"
  org_id                     = "123456789"
  folder_id                  = "111111111"
  billing_account            = "ABCDEF-123456-ABCDEF"
  project_admin_group_email  = "payments-admins@example.com"
  shared_vpc_host_project_id = "acme-dev-host-abcd"
  shared_vpc_subnets = {
    app = { region = "europe-west1", subnet_name = "app" }
  }
}

run "project_created_through_primitive" {
  command = apply

  assert {
    condition     = module.project.project_id == "payments-1a2b" && module.project.name == "payments"
    error_message = "Project ID must be <project_name>-<4 hex> and the display name the project_name."
  }

  assert {
    condition     = module.project.parent == "folders/111111111"
    error_message = "The project must be created under folder_id."
  }

  assert {
    condition     = output.project_id == "payments-1a2b"
    error_message = "project_id output must come from the primitive."
  }
}

run "gke_api_is_opt_in" {
  command = plan

  assert {
    condition     = !contains(module.project.services, "container.googleapis.com")
    error_message = "container.googleapis.com must NOT be enabled unless enable_gke is set."
  }

  assert {
    condition     = contains(module.project.services, "compute.googleapis.com") && contains(module.project.services, "servicenetworking.googleapis.com")
    error_message = "compute and servicenetworking APIs must always be enabled."
  }
}

run "gke_api_enabled_by_flag" {
  command = plan

  variables {
    enable_gke    = true
    activate_apis = ["run.googleapis.com", "compute.googleapis.com"]
  }

  assert {
    condition     = contains(module.project.services, "container.googleapis.com") && contains(module.project.services, "run.googleapis.com")
    error_message = "enable_gke must add container.googleapis.com alongside activate_apis."
  }

  assert {
    condition     = length(module.project.services) == 4
    error_message = "Duplicate APIs from activate_apis must be de-duplicated."
  }
}

run "gke_network_user_implies_gke_api" {
  command = plan

  variables {
    enable_gke_network_user = true
  }

  assert {
    condition     = contains(module.project.services, "container.googleapis.com")
    error_message = "enable_gke_network_user must imply the container API (the GKE robot SA only exists once it is enabled)."
  }

  assert {
    condition     = contains(keys(google_compute_subnetwork_iam_member.network_users), "app/gke-robot")
    error_message = "enable_gke_network_user must grant the GKE robot SA networkUser."
  }
}

run "shared_vpc_attachment_and_subnet_grants" {
  command = plan

  assert {
    condition     = module.project.shared_vpc_host_project_id == "acme-dev-host-abcd"
    error_message = "The project must be attached to the Shared VPC host."
  }

  assert {
    condition     = sort(keys(google_compute_subnetwork_iam_member.network_users)) == sort(["app/default-sa", "app/admin-group", "app/cloud-services"])
    error_message = "Without GKE, exactly the project SA, admin group and Cloud Services robot get networkUser."
  }
}

run "no_shared_vpc_when_disabled" {
  command = plan

  variables {
    enable_shared_vpc_attachment = false
  }

  assert {
    condition     = module.project.shared_vpc_host_project_id == null && length(google_compute_subnetwork_iam_member.network_users) == 0
    error_message = "enable_shared_vpc_attachment = false must skip the attachment and subnet grants."
  }
}

run "default_sa_disabled_and_project_sa_created" {
  command = plan

  assert {
    condition     = google_project_default_service_accounts.this[0].action == "DISABLE"
    error_message = "The default compute SA must be disabled by default (upstream factory parity)."
  }

  assert {
    condition     = google_service_account.project[0].account_id == "project-service-account"
    error_message = "The dedicated project-service-account must be created by default."
  }
}

run "keep_default_sa_and_skip_project_sa" {
  command = plan

  variables {
    default_service_account_action = "KEEP"
    create_project_service_account = false
  }

  assert {
    condition     = length(google_project_default_service_accounts.this) == 0 && length(google_service_account.project) == 0
    error_message = "KEEP / create_project_service_account = false must create neither resource."
  }

  assert {
    condition     = !contains(keys(google_compute_subnetwork_iam_member.network_users), "app/default-sa")
    error_message = "No project SA means no project-SA networkUser grant."
  }
}

run "org_parent_when_no_folder" {
  command = plan

  variables {
    folder_id = null
  }

  assert {
    condition     = module.project.parent == "organizations/123456789"
    error_message = "With folder_id = null the project must be created under the organization."
  }
}
