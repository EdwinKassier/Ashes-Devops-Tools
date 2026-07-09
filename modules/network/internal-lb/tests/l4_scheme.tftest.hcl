# Regression test: the L4 (is_l7 = false) path must use the INTERNAL passthrough
# scheme with backend_service on the forwarding rule (not a target proxy), and
# must NOT set locality_lb_policy (rejected for INTERNAL passthrough backends).
# The L7 (is_l7 = true) path must keep INTERNAL_MANAGED with a target proxy.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "test-lb"
  region     = "europe-west1"
  network    = "projects/mock-project/global/networks/mock-vpc"
  subnet     = "projects/mock-project/regions/europe-west1/subnetworks/mock-subnet"
  backends = [
    {
      group = "projects/mock-project/zones/europe-west1-b/instanceGroups/mock-ig"
    }
  ]
}

run "l4_uses_internal_scheme_and_backend_service" {
  command = plan

  variables {
    is_l7 = false
  }

  assert {
    condition     = google_compute_region_backend_service.backend.load_balancing_scheme == "INTERNAL"
    error_message = "L4 backend service must use load_balancing_scheme INTERNAL"
  }

  assert {
    condition     = google_compute_region_backend_service.backend.locality_lb_policy == null
    error_message = "L4 (INTERNAL passthrough) backend service must not set locality_lb_policy"
  }

  assert {
    condition     = google_compute_forwarding_rule.forwarding_rule.load_balancing_scheme == "INTERNAL"
    error_message = "L4 forwarding rule must use load_balancing_scheme INTERNAL"
  }

  # backend_service is a computed self_link (unknown at plan), so we prove the
  # L4 branch by asserting target is the statically-null side of the ternary.
  assert {
    condition     = google_compute_forwarding_rule.forwarding_rule.target == null
    error_message = "L4 forwarding rule must not set target (it must use backend_service)"
  }
}

run "l7_uses_internal_managed_scheme_and_target_proxy" {
  command = plan

  variables {
    is_l7 = true
    host_rules = [
      {
        hosts        = ["example.com"]
        path_matcher = "main"
      }
    ]
    path_matchers = [
      {
        name            = "main"
        default_service = "projects/mock-project/regions/europe-west1/backendServices/mock-bs"
      }
    ]
  }

  assert {
    condition     = google_compute_region_backend_service.backend.load_balancing_scheme == "INTERNAL_MANAGED"
    error_message = "L7 backend service must use load_balancing_scheme INTERNAL_MANAGED"
  }

  assert {
    condition     = google_compute_forwarding_rule.forwarding_rule.load_balancing_scheme == "INTERNAL_MANAGED"
    error_message = "L7 forwarding rule must use load_balancing_scheme INTERNAL_MANAGED"
  }

  # target is a computed proxy self_link (unknown at plan), so we prove the
  # L7 branch by asserting backend_service is the statically-null side.
  assert {
    condition     = google_compute_forwarding_rule.forwarding_rule.backend_service == null
    error_message = "L7 forwarding rule must not set backend_service (it must use a target proxy)"
  }
}
