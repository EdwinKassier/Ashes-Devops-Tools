mock_provider "google" {}

variables {
  project_id      = "acme-dev-app-1a2b"
  parent          = "folders/123456789012"
  billing_account = "ABCDEF-123456-ABCDEF"
}

run "minimal_project_baseline" {
  command = plan

  assert {
    condition     = google_project.this.project_id == "acme-dev-app-1a2b"
    error_message = "project_id must be used verbatim (no naming scheme inside the primitive)."
  }

  assert {
    condition     = google_project.this.name == "acme-dev-app-1a2b"
    error_message = "name must default to project_id."
  }

  assert {
    condition     = google_project.this.folder_id == "123456789012" && google_project.this.org_id == null
    error_message = "A folders/ parent must set folder_id (numeric) and leave org_id null."
  }

  assert {
    condition     = google_project.this.auto_create_network == false
    error_message = "The default network must never be created."
  }

  assert {
    condition     = google_project.this.deletion_policy == "PREVENT"
    error_message = "deletion_policy must default to PREVENT."
  }

  assert {
    condition     = google_project.this.billing_account == "ABCDEF-123456-ABCDEF"
    error_message = "billing_account must be passed through."
  }

  assert {
    condition = (
      length(google_project_service.this) == 0 &&
      length(google_compute_shared_vpc_service_project.this) == 0 &&
      length(google_project_iam_member.this) == 0 &&
      length(google_essential_contacts_contact.this) == 0 &&
      length(google_resource_manager_lien.this) == 0 &&
      length(google_tags_tag_binding.this) == 0
    )
    error_message = "All optional features must be off by default."
  }
}

run "organization_parent" {
  command = plan

  variables {
    parent = "organizations/987654321"
    name   = "Acme Admin"
  }

  assert {
    condition     = google_project.this.org_id == "987654321" && google_project.this.folder_id == null
    error_message = "An organizations/ parent must set org_id and leave folder_id null."
  }

  assert {
    condition     = google_project.this.name == "Acme Admin"
    error_message = "An explicit name must override the project_id default."
  }
}

run "services_enabled_without_disable_on_destroy" {
  command = plan

  variables {
    services = ["compute.googleapis.com", "iam.googleapis.com", "compute.googleapis.com"]
  }

  assert {
    condition     = length(google_project_service.this) == 2
    error_message = "Services must be de-duplicated (one resource per API)."
  }

  assert {
    condition = alltrue([
      for s in google_project_service.this : s.disable_on_destroy == false && s.disable_dependent_services == false
    ])
    error_message = "Services must never be disabled on destroy."
  }

  assert {
    condition     = google_project_service.this["iam.googleapis.com"].project == "acme-dev-app-1a2b"
    error_message = "Services must target the created project."
  }

  assert {
    condition     = output.services == tolist(["compute.googleapis.com", "iam.googleapis.com"])
    error_message = "services output must list the enabled APIs, sorted."
  }
}

run "shared_vpc_attachment" {
  command = plan

  variables {
    services                   = ["compute.googleapis.com"]
    shared_vpc_host_project_id = "acme-dev-host-1a2b"
  }

  assert {
    condition     = google_compute_shared_vpc_service_project.this[0].host_project == "acme-dev-host-1a2b"
    error_message = "Attachment must target the host project."
  }

  assert {
    condition     = google_compute_shared_vpc_service_project.this[0].service_project == "acme-dev-app-1a2b"
    error_message = "Attachment must attach the created project."
  }

  assert {
    condition     = output.shared_vpc_host_project_id == "acme-dev-host-1a2b"
    error_message = "shared_vpc_host_project_id output must echo the host."
  }
}

run "additive_iam_flattened_per_member" {
  command = plan

  variables {
    iam = {
      "roles/storage.admin"  = ["group:data@example.com", "user:alice@example.com"]
      "roles/bigquery.admin" = ["group:data@example.com"]
    }
  }

  assert {
    condition     = length(google_project_iam_member.this) == 3
    error_message = "iam must produce one additive member binding per (role, member)."
  }

  assert {
    condition     = google_project_iam_member.this["roles/storage.admin|user:alice@example.com"].member == "user:alice@example.com"
    error_message = "Bindings must be keyed role|member."
  }
}

run "essential_contacts_lien_and_tags" {
  command = plan

  variables {
    essential_contacts = {
      "secops@example.com" = ["SECURITY", "TECHNICAL"]
    }
    lien_reason = "Foundation project"
    tag_bindings = {
      environment = "tagValues/1234567890"
    }
  }

  assert {
    condition     = google_essential_contacts_contact.this["secops@example.com"].parent == "projects/acme-dev-app-1a2b"
    error_message = "Essential contact must be created on the project."
  }

  assert {
    condition     = google_essential_contacts_contact.this["secops@example.com"].language_tag == "en"
    error_message = "Essential contacts language must default to en."
  }

  assert {
    condition     = google_resource_manager_lien.this[0].restrictions == tolist(["resourcemanager.projects.delete"])
    error_message = "Lien must restrict project deletion."
  }

  assert {
    condition     = google_resource_manager_lien.this[0].reason == "Foundation project"
    error_message = "Lien must carry lien_reason."
  }

  assert {
    condition     = google_tags_tag_binding.this["environment"].tag_value == "tagValues/1234567890"
    error_message = "Tag binding must bind the supplied tag value."
  }
}

run "deletion_policy_override" {
  command = plan

  variables {
    deletion_policy = "DELETE"
    labels          = { environment = "sandbox" }
  }

  assert {
    condition     = google_project.this.deletion_policy == "DELETE"
    error_message = "deletion_policy must be overridable."
  }

  assert {
    condition     = google_project.this.labels["environment"] == "sandbox"
    error_message = "labels must be applied to the project."
  }
}
