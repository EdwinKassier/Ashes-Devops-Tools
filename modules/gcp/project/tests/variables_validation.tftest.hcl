mock_provider "google" {}

variables {
  project_id = "acme-dev-app-1a2b"
  parent     = "folders/123456789012"
}

run "rejects_invalid_project_id" {
  command = plan
  variables {
    project_id = "Acme_Project"
  }
  expect_failures = [var.project_id]
}

run "rejects_too_short_project_id" {
  command = plan
  variables {
    project_id = "abc"
  }
  expect_failures = [var.project_id]
}

run "rejects_project_id_ending_in_hyphen" {
  command = plan
  variables {
    project_id = "acme-project-"
  }
  expect_failures = [var.project_id]
}

run "rejects_short_name" {
  command = plan
  variables {
    name = "hub"
  }
  expect_failures = [var.name]
}

run "rejects_bare_numeric_parent" {
  command = plan
  variables {
    parent = "123456789012"
  }
  expect_failures = [var.parent]
}

run "rejects_projects_parent" {
  command = plan
  variables {
    parent = "projects/acme"
  }
  expect_failures = [var.parent]
}

run "rejects_malformed_billing_account" {
  command = plan
  variables {
    billing_account = "billingAccounts/ABCDEF-123456-ABCDEF"
  }
  expect_failures = [var.billing_account]
}

run "rejects_uppercase_label_key" {
  command = plan
  variables {
    labels = { Environment = "dev" }
  }
  expect_failures = [var.labels]
}

run "rejects_unknown_deletion_policy" {
  command = plan
  variables {
    deletion_policy = "RETAIN"
  }
  expect_failures = [var.deletion_policy]
}

run "rejects_non_api_service" {
  command = plan
  variables {
    services = ["compute"]
  }
  expect_failures = [var.services]
}

run "rejects_shared_vpc_without_compute_api" {
  command = plan
  variables {
    shared_vpc_host_project_id = "acme-dev-host-1a2b"
  }
  expect_failures = [var.shared_vpc_host_project_id]
}

run "rejects_invalid_shared_vpc_host" {
  command = plan
  variables {
    services                   = ["compute.googleapis.com"]
    shared_vpc_host_project_id = "Not A Project"
  }
  expect_failures = [var.shared_vpc_host_project_id]
}

run "rejects_malformed_iam_role" {
  command = plan
  variables {
    iam = { "storage.admin" = ["group:data@example.com"] }
  }
  expect_failures = [var.iam]
}

run "rejects_unprefixed_iam_member" {
  command = plan
  variables {
    iam = { "roles/storage.admin" = ["data@example.com"] }
  }
  expect_failures = [var.iam]
}

run "rejects_invalid_contact_email" {
  command = plan
  variables {
    essential_contacts = { "not-an-email" = ["ALL"] }
  }
  expect_failures = [var.essential_contacts]
}

run "rejects_unknown_contact_category" {
  command = plan
  variables {
    essential_contacts = { "secops@example.com" = ["PAGER"] }
  }
  expect_failures = [var.essential_contacts]
}

run "rejects_empty_contact_categories" {
  command = plan
  variables {
    essential_contacts = { "secops@example.com" = [] }
  }
  expect_failures = [var.essential_contacts]
}

run "rejects_invalid_language_tag" {
  command = plan
  variables {
    essential_contacts_language = "English"
  }
  expect_failures = [var.essential_contacts_language]
}

run "rejects_blank_lien_reason" {
  command = plan
  variables {
    lien_reason = "   "
  }
  expect_failures = [var.lien_reason]
}

run "rejects_malformed_tag_value" {
  command = plan
  variables {
    tag_bindings = { environment = "tagKeys/123" }
  }
  expect_failures = [var.tag_bindings]
}

run "accepts_full_valid_configuration" {
  command = plan
  variables {
    name                       = "Acme App Dev"
    parent                     = "organizations/987654321"
    billing_account            = "ABCDEF-123456-ABCDEF"
    labels                     = { environment = "dev", team = "app" }
    deletion_policy            = "ABANDON"
    services                   = ["compute.googleapis.com", "essentialcontacts.googleapis.com"]
    shared_vpc_host_project_id = "acme-dev-host-1a2b"
    iam                        = { "roles/viewer" = ["group:app@example.com"] }
    essential_contacts         = { "secops@example.com" = ["ALL"] }
    lien_reason                = "Protected"
    tag_bindings               = { env = "tagValues/42" }
  }
}

run "rejects_label_value_with_space" {
  command = plan
  variables {
    labels = { organization = "My Organization" }
  }
  expect_failures = [var.labels]
}
