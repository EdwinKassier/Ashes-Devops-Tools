# Resource-assertion tests for the network/cdn module.
# Asserts that var.enable_cdn actually toggles both the backend service's
# enable_cdn attribute AND the presence of the cdn_policy dynamic block — prior
# tests only validated inputs (audit round-3 §D8 / finding #10).

mock_provider "google" {}

variables {
  project_id = "mock-project"
  lb_name    = "test-lb"
  domains    = ["example.com"]
}

run "enable_cdn_true_wires_cdn_policy" {
  command = plan

  variables {
    enable_cdn = true
  }

  assert {
    condition     = google_compute_backend_service.default.enable_cdn == true
    error_message = "backend service enable_cdn must reflect var.enable_cdn = true."
  }

  assert {
    condition     = length(google_compute_backend_service.default.cdn_policy) == 1
    error_message = "The cdn_policy block must be present when enable_cdn = true."
  }
}

run "enable_cdn_false_omits_cdn_policy" {
  command = plan

  variables {
    enable_cdn = false
  }

  assert {
    condition     = google_compute_backend_service.default.enable_cdn == false
    error_message = "backend service enable_cdn must be false when disabled."
  }

  assert {
    condition     = length(google_compute_backend_service.default.cdn_policy) == 0
    error_message = "The cdn_policy block must be omitted when enable_cdn = false."
  }
}
