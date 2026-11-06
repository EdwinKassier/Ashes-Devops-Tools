# Regression test: api_config_id must be STABLE and content-derived (a hash of
# the OpenAPI spec), not time-derived. Previously it embedded timestamp(), which
# forced the api-config resource to be replaced on every apply.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  region                = "us-central1"
  project_id            = "mock-project"
  service_account_email = "sa@mock-project.iam.gserviceaccount.com"
  api_id                = "my-api-v1"
}

run "api_config_id_is_content_derived_and_stable" {
  command = plan

  # With no managed_service_ids, openapi_content == var.openapi_spec, so the id
  # is fully deterministic across plans given identical inputs. A timestamp()-based
  # id could never satisfy this equality.
  assert {
    condition     = google_api_gateway_api_config.api_config.api_config_id == "${var.api_id}-config-${substr(sha256(var.openapi_spec), 0, 12)}"
    error_message = "api_config_id must be derived from a hash of the OpenAPI spec (stable across plans), not from timestamp()"
  }

  # The suffix must be a 12-char lowercase-hex hash, never a 14-digit timestamp.
  assert {
    condition     = can(regex("^my-api-v1-config-[0-9a-f]{12}$", google_api_gateway_api_config.api_config.api_config_id))
    error_message = "api_config_id must end in a 12-char content hash, not a timestamp"
  }
}

run "labels_use_canonical_managed_by_key" {
  command = plan

  assert {
    condition     = google_api_gateway_gateway.gateway.labels["managed-by"] == "terraform" && !contains(keys(google_api_gateway_gateway.gateway.labels), "managed_by")
    error_message = "the default labels must use the canonical managed-by key, not managed_by"
  }
}

run "legacy_managed_by_key_is_rewritten" {
  command = plan

  variables {
    labels = { managed_by = "legacy-pipeline", team = "edge" }
  }

  assert {
    condition     = google_api_gateway_api.api.labels == tomap({ "managed-by" = "legacy-pipeline", team = "edge" })
    error_message = "a legacy managed_by label must be rewritten to managed-by (other keys untouched)"
  }

  assert {
    condition     = google_api_gateway_gateway.gateway.labels == google_api_gateway_api.api.labels
    error_message = "the gateway and API must carry the same normalized labels"
  }
}

run "explicit_managed_by_wins_over_legacy_key" {
  command = plan

  variables {
    labels = { managed_by = "old", "managed-by" = "terraform" }
  }

  assert {
    condition     = google_api_gateway_api.api.labels == tomap({ "managed-by" = "terraform" })
    error_message = "an explicit managed-by label must win over the legacy managed_by key"
  }
}
