# C2: workload SAs are granted roles ONLY on their own environment folder (never
# the org node or another env's folder), plan SAs only read-only roles, and the
# network-hub SAs only on the shared folder.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_prefix          = "my-org"
  organization_name       = "example"
  default_billing_account = "ABCDEF-123456-789012"
  admin_project_id        = "mock-admin-project"
  suffix                  = "abcd1234"
  folders = {
    shared = { id = "folders/100", name = "folders/100", display_name = "Shared" }
    dev    = { id = "folders/111", name = "folders/111", display_name = "Development" }
    prod   = { id = "folders/222", name = "folders/222", display_name = "Production" }
  }
  environments = {
    dev = {
      display_name = "Development"
      description  = "Development environment"
      projects = {
        host = { name = "host", labels = {} }
      }
    }
  }
  workload_service_accounts = {
    dev = {
      plan  = "my-org-wl-dev-plan@admin.iam.gserviceaccount.com"
      apply = "my-org-wl-dev-apply@admin.iam.gserviceaccount.com"
    }
    prod = {
      plan  = "my-org-wl-prod-plan@admin.iam.gserviceaccount.com"
      apply = "my-org-wl-prod-apply@admin.iam.gserviceaccount.com"
    }
  }
  workload_folder_roles = {
    plan  = ["roles/viewer", "roles/iam.securityReviewer"]
    apply = ["roles/compute.admin", "roles/resourcemanager.projectIamAdmin"]
  }
  network_service_accounts = {
    plan  = "my-org-network-hub-plan@admin.iam.gserviceaccount.com"
    apply = "my-org-network-hub-apply@admin.iam.gserviceaccount.com"
  }
  network_folder_roles = {
    plan  = ["roles/compute.viewer"]
    apply = ["roles/compute.networkAdmin"]
  }
}

run "workload_sas_scoped_to_own_env_folder" {
  command = plan

  assert {
    condition     = length(google_folder_iam_member.workload_sa_folder_roles) == 8
    error_message = "2 envs x (2 plan + 2 apply) roles = 8 folder grants expected."
  }

  assert {
    condition = alltrue([
      for k, m in google_folder_iam_member.workload_sa_folder_roles :
      m.folder == (startswith(k, "dev|") ? "folders/111" : "folders/222") && strcontains(m.member, startswith(k, "dev|") ? "-wl-dev-" : "-wl-prod-")
    ])
    error_message = "Each workload SA must be granted only on its own environment folder."
  }

  assert {
    condition = alltrue([
      for k, m in google_folder_iam_member.workload_sa_folder_roles :
      endswith(m.member, strcontains(k, "|plan|") ? "-plan@admin.iam.gserviceaccount.com" : "-apply@admin.iam.gserviceaccount.com")
    ])
    error_message = "Plan roles must go to the plan SA and apply roles to the apply SA."
  }

  assert {
    condition = length([
      for k, m in google_folder_iam_member.workload_sa_folder_roles : k
      if strcontains(k, "|plan|") && can(regex("(?i)(admin|editor|owner)", m.role))
    ]) == 0
    error_message = "Workload plan SAs must hold no admin/editor/owner role."
  }
}

run "network_sas_scoped_to_shared_folder" {
  command = plan

  assert {
    condition = length(google_folder_iam_member.network_sa_folder_roles) == 2 && alltrue([
      for m in google_folder_iam_member.network_sa_folder_roles : m.folder == "folders/100"
    ])
    error_message = "network-hub SAs must be granted only on the shared folder."
  }
}

run "no_grants_by_default" {
  command = plan

  variables {
    workload_service_accounts = {}
    network_service_accounts  = null
  }

  assert {
    condition     = length(google_folder_iam_member.workload_sa_folder_roles) == 0 && length(google_folder_iam_member.network_sa_folder_roles) == 0
    error_message = "No automation grants are made unless SAs are supplied."
  }
}

run "rejects_workload_sa_for_unknown_env_folder" {
  command         = plan
  expect_failures = [var.workload_service_accounts]

  variables {
    workload_service_accounts = {
      qa = {
        plan  = "my-org-wl-qa-plan@admin.iam.gserviceaccount.com"
        apply = "my-org-wl-qa-apply@admin.iam.gserviceaccount.com"
      }
    }
  }
}

run "rejects_same_sa_for_plan_and_apply" {
  command         = plan
  expect_failures = [var.workload_service_accounts]

  variables {
    workload_service_accounts = {
      dev = {
        plan  = "terraform-admin@admin.iam.gserviceaccount.com"
        apply = "terraform-admin@admin.iam.gserviceaccount.com"
      }
    }
  }
}

run "rejects_owner_role" {
  command         = plan
  expect_failures = [var.workload_folder_roles]

  variables {
    workload_folder_roles = {
      plan  = []
      apply = ["roles/owner"]
    }
  }
}
