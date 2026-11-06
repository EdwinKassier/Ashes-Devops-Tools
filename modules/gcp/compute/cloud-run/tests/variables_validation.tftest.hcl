# Variable validation tests for the cloud-run module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id            = "mock-project-id"
  location              = "europe-west1"
  name                  = "mock-service"
  image                 = "europe-west1-docker.pkg.dev/mock-project-id/apps/api:1.0.0"
  service_account_email = "run-sa@mock-project-id.iam.gserviceaccount.com"
}

# ── var.project_id ────────────────────────────────────────────────────────────
run "valid_project_id_accepted" {
  command = plan
  variables { project_id = "my-project-id" }
}

run "invalid_project_id_rejected" {
  command         = plan
  expect_failures = [var.project_id]
  variables { project_id = "INVALID PROJECT!" }
}

# ── var.location ──────────────────────────────────────────────────────────────
run "invalid_location_rejected" {
  command         = plan
  expect_failures = [var.location]
  variables { location = "not a region" }
}

# ── var.name ──────────────────────────────────────────────────────────────────
run "invalid_name_rejected" {
  command         = plan
  expect_failures = [var.name]
  variables { name = "Invalid_Name" }
}

# ── var.image ─────────────────────────────────────────────────────────────────
run "empty_image_rejected" {
  command         = plan
  expect_failures = [var.image]
  variables { image = "   " }
}

# ── var.service_account_email ─────────────────────────────────────────────────
run "invalid_service_account_rejected" {
  command         = plan
  expect_failures = [var.service_account_email]
  variables { service_account_email = "not-an-sa@example.com" }
}

# ── var.ingress ───────────────────────────────────────────────────────────────
run "default_ingress_is_internal_lb" {
  command = plan
  assert {
    condition     = var.ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    error_message = "ingress must default to the internal load balancer policy."
  }
}

run "invalid_ingress_rejected" {
  command         = plan
  expect_failures = [var.ingress]
  variables { ingress = "INGRESS_TRAFFIC_EVERYWHERE" }
}

# ── var.concurrency ───────────────────────────────────────────────────────────
run "concurrency_above_max_rejected" {
  command         = plan
  expect_failures = [var.concurrency]
  variables { concurrency = 1001 }
}

# ── scaling: max must not be below min ────────────────────────────────────────
run "max_below_min_rejected" {
  command         = plan
  expect_failures = [var.max_instance_count]
  variables {
    min_instance_count = 5
    max_instance_count = 2
  }
}

run "negative_min_instances_rejected" {
  command         = plan
  expect_failures = [var.min_instance_count]
  variables { min_instance_count = -1 }
}

# ── var.vpc_access.egress ─────────────────────────────────────────────────────
run "invalid_vpc_egress_rejected" {
  command         = plan
  expect_failures = [var.vpc_access]
  variables {
    vpc_access = {
      connector = "projects/mock-project-id/locations/europe-west1/connectors/c"
      egress    = "SOME_TRAFFIC"
    }
  }
}

# invoker_iam_disabled + INGRESS_TRAFFIC_ALL is an unprotected public run.app URL:
# rejected unless deliberately acknowledged.
run "rejects_unacknowledged_public_run_url" {
  command = plan

  variables {
    enable_unauthenticated = true
    ingress                = "INGRESS_TRAFFIC_ALL"
  }

  expect_failures = [var.public_access_mode]
}

run "allows_acknowledged_public_run_url" {
  command = plan

  variables {
    enable_unauthenticated = true
    ingress                = "INGRESS_TRAFFIC_ALL"
    allow_public_run_url   = true
  }
}
