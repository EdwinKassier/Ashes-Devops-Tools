# Resource-assertion tests for the cloud-run module.
# Proves the module plans a Cloud Run v2 service with the expected, secure-by-default
# attributes and that the unauthenticated binding is created only on opt-in.

mock_provider "google" {}

variables {
  project_id            = "mock-project-id"
  location              = "europe-west1"
  name                  = "mock-service"
  image                 = "europe-west1-docker.pkg.dev/mock-project-id/apps/api:1.0.0"
  service_account_email = "run-sa@mock-project-id.iam.gserviceaccount.com"
}

run "service_plans_with_secure_defaults" {
  command = plan

  variables {
    secret_env_vars = [
      { name = "DATABASE_URL", secret = "database-url", version = "latest" },
    ]
  }

  assert {
    condition     = google_cloud_run_v2_service.this.name == "mock-service"
    error_message = "service name must match var.name."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.location == "europe-west1"
    error_message = "service must be planned in the supplied location."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    error_message = "ingress must default to the internal load balancer policy."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.deletion_protection == true
    error_message = "deletion_protection must default to true."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].service_account == "run-sa@mock-project-id.iam.gserviceaccount.com"
    error_message = "service must run as the supplied dedicated service account."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].image == "europe-west1-docker.pkg.dev/mock-project-id/apps/api:1.0.0"
    error_message = "container image must match var.image."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].scaling[0].min_instance_count == 0
    error_message = "min_instance_count must default to 0 (scale to zero)."
  }

  # Secret env var must be wired via secret_key_ref, never a plaintext value.
  # env is a TypeSet, so iterate rather than index.
  assert {
    condition = anytrue([
      for e in google_cloud_run_v2_service.this.template[0].containers[0].env :
      try(e.value_source[0].secret_key_ref[0].secret == "database-url", false)
    ])
    error_message = "secret env var must reference the Secret Manager secret via secret_key_ref."
  }

  # Private by default: no unauthenticated invoker binding.
  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.unauthenticated) == 0
    error_message = "the service must be private by default (no allUsers invoker binding)."
  }
}

run "unauthenticated_binding_created_on_opt_in" {
  command = plan

  variables {
    enable_unauthenticated = true
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.unauthenticated) == 1
    error_message = "enabling unauthenticated access must create exactly one invoker binding."
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.unauthenticated[0].member == "allUsers"
    error_message = "the unauthenticated binding must grant access to allUsers."
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.unauthenticated[0].role == "roles/run.invoker"
    error_message = "the unauthenticated binding must grant roles/run.invoker."
  }
}
