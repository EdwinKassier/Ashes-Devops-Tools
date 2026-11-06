# Variable validation tests for the app-services stage.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id     = "acme-dev-host-abcd"
  project_number = "222222222222"
  region         = "europe-west1"
  environment    = "dev"
  network_id     = "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
  subnetwork_id  = "projects/acme-dev-host-abcd/regions/europe-west1/subnetworks/private"
}

run "rejects_repository_name_instead_of_id" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services              = { api = { github = { repository_id = "acme/api" } } }
  }

  expect_failures = [var.services]
}

run "rejects_github_without_wif_pool" {
  command = plan

  variables {
    services = { api = { github = { repository_id = "123" } } }
  }

  expect_failures = [var.services]
}

run "rejects_short_ref" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services              = { api = { github = { repository_id = "123", ref = "main" } } }
  }

  expect_failures = [var.services]
}

run "rejects_invalid_service_key" {
  command = plan

  variables {
    services = { "Bad_Name" = {} }
  }

  expect_failures = [var.services]
}

run "rejects_unknown_ingress" {
  command = plan

  variables {
    services = { api = { ingress = "PUBLIC" } }
  }

  expect_failures = [var.services]
}

run "rejects_public_invoker_on_internal_ingress" {
  command = plan

  variables {
    services = { api = { enable_unauthenticated = true } }
  }

  expect_failures = [var.services]
}

# A public service must sit behind the external ALB: INGRESS_TRAFFIC_ALL with the
# Invoker IAM check disabled would publish an unprotected run.app URL.
run "rejects_public_invoker_on_all_ingress" {
  command = plan

  variables {
    services = { api = { enable_unauthenticated = true, ingress = "INGRESS_TRAFFIC_ALL" } }
  }

  expect_failures = [var.services]
}

run "requires_subnetwork_for_services" {
  command = plan

  variables {
    subnetwork_id = null
    services      = { api = {} }
  }

  expect_failures = [var.subnetwork_id]
}

run "requires_project_number_for_wif" {
  command = plan

  variables {
    project_number        = null
    enable_app_deploy_wif = true
  }

  expect_failures = [var.project_number]
}

run "rejects_blank_bootstrap_image" {
  command = plan

  variables {
    bootstrap_image = ""
  }

  expect_failures = [var.bootstrap_image]
}

run "rejects_error_ratio_above_one" {
  command         = plan
  expect_failures = [var.services]
  variables {
    services = { api = { alerts = { error_ratio_threshold = 5 } } }
  }
}

run "rejects_bad_alert_duration" {
  command         = plan
  expect_failures = [var.services]
  variables {
    services = { api = { alerts = { duration = "5m" } } }
  }
}

run "rejects_pubsub_ack_deadline_below_minimum" {
  command         = plan
  expect_failures = [var.services]
  variables {
    services = { api = { pubsub = { enabled = true, ack_deadline_seconds = 5 } } }
  }
}

run "rejects_pubsub_max_delivery_attempts_below_minimum" {
  command         = plan
  expect_failures = [var.services]
  variables {
    services = { api = { pubsub = { enabled = true, max_delivery_attempts = 3 } } }
  }
}

run "rejects_pubsub_without_project_number" {
  command         = plan
  expect_failures = [var.project_number]
  variables {
    project_number = null
    services       = { api = { pubsub = { enabled = true } } }
  }
}

run "rejects_bad_notification_channel_id" {
  command         = plan
  expect_failures = [var.alert_notification_channel_ids]
  variables {
    alert_notification_channel_ids = ["ops@example.com"]
  }
}

run "rejects_bad_pubsub_kms_key" {
  command         = plan
  expect_failures = [var.pubsub_kms_key_name]
  variables {
    pubsub_kms_key_name = "pubsub-key"
  }
}
