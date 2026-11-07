# Variable validation tests for stages/environment.
# All runs use mock providers so no GCP credentials are required.

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
    }
  }
}
mock_provider "google-beta" {}

variables {
  environment          = "dev"
  project_prefix       = "acme"
  org_id               = "123456789012"
  billing_account      = "billingAccounts/000000-111111-222222"
  admin_project_number = "111111111111"

  host_project = {
    project_id     = "acme-dev-host-abcd"
    project_number = "222222222222"
    folder_id      = "folders/111"
    region         = "europe-west1"
    cidr_block     = "10.10.0.0/16"
  }
}

run "accepts_minimal_inputs" {
  command = plan
}

run "rejects_uppercase_environment" {
  command = plan

  variables {
    environment = "Dev"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_project_prefix" {
  command = plan

  variables {
    project_prefix = "1acme"
  }

  expect_failures = [var.project_prefix]
}

run "rejects_prefixed_org_id" {
  command = plan

  variables {
    org_id = "organizations/123456789012"
  }

  expect_failures = [var.org_id]
}

run "rejects_invalid_cidr_block" {
  command = plan

  variables {
    host_project = {
      project_id     = "acme-dev-host-abcd"
      project_number = "222222222222"
      folder_id      = "folders/111"
      region         = "europe-west1"
      cidr_block     = "10.10.0.0"
    }
  }

  expect_failures = [var.host_project]
}

run "rejects_flow_log_sampling_above_one" {
  command = plan

  variables {
    network = { flow_logs = { sampling = 1.5 } }
  }

  expect_failures = [var.network]
}

run "rejects_unknown_psc_target" {
  command = plan

  variables {
    network = { private_service_connect_target = "restricted" }
  }

  expect_failures = [var.network]
}

run "rejects_unknown_connectivity" {
  command = plan

  variables {
    hub = { connectivity = "transit" }
  }

  expect_failures = [var.hub]
}

run "rejects_owasp_sensitivity_out_of_range" {
  command = plan

  variables {
    cloud_armor = { enabled = true, owasp_sensitivity = 5 }
  }

  expect_failures = [var.cloud_armor]
}

run "rejects_negative_budget" {
  command = plan

  variables {
    budget = { monthly_limit = -1 }
  }

  expect_failures = [var.budget]
}

run "rejects_lowercase_currency" {
  command = plan

  variables {
    budget = { monthly_limit = 100, currency = "usd" }
  }

  expect_failures = [var.budget]
}

run "rejects_invalid_service_team_key" {
  command = plan

  variables {
    service_teams = {
      Payments = {
        project_admin_group_email = "payments-admins@acme.test"
        shared_vpc_subnets        = { private = { region = "europe-west1", subnet_name = "s" } }
      }
    }
  }

  expect_failures = [var.service_teams]
}

run "rejects_invalid_service_team_email" {
  command = plan

  variables {
    service_teams = {
      payments = {
        project_admin_group_email = "payments-admins"
        shared_vpc_subnets        = { private = { region = "europe-west1", subnet_name = "s" } }
      }
    }
  }

  expect_failures = [var.service_teams]
}

run "rejects_attachment_without_subnets" {
  command = plan

  variables {
    service_teams = {
      payments = { project_admin_group_email = "payments-admins@acme.test" }
    }
  }

  expect_failures = [var.service_teams]
}

run "rejects_unprefixed_bridge_accessor" {
  command = plan

  variables {
    saas_secret_bridge       = { enabled = true, accessor_members = ["app@acme-dev-host-abcd.iam.gserviceaccount.com"] }
    saas_secret_bridge_value = "{}"
  }

  expect_failures = [var.saas_secret_bridge]
}

run "rejects_enabled_bridge_without_value" {
  command = plan

  variables {
    saas_secret_bridge = { enabled = true }
  }

  expect_failures = [var.saas_secret_bridge_value]
}

run "rejects_public_ingress_for_unknown_service" {
  command = plan

  variables {
    app_services   = { api = {} }
    public_ingress = { billing = { domains = ["billing.dev.acme.example"] } }
  }

  expect_failures = [var.public_ingress]
}
