# Behavior tests for the artifact_registry module: configurable Maven options,
# multi-region validation, and per-format repository URLs.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  kms_key_name = "projects/mock-project/locations/us-central1/keyRings/test-ring/cryptoKeys/test-key"
  repositories = {}
}

# ── Maven options are configurable (not swallowed by the closed object type) ─────

run "maven_config_is_configurable" {
  command = plan

  variables {
    repositories = {
      "my-maven-repo" = {
        description               = "Maven repo"
        format                    = "MAVEN"
        allow_snapshot_overwrites = true
        version_policy            = "SNAPSHOT"
      }
    }
  }

  assert {
    condition     = google_artifact_registry_repository.repo["my-maven-repo"].maven_config[0].allow_snapshot_overwrites == true
    error_message = "allow_snapshot_overwrites must flow through to maven_config"
  }

  assert {
    condition     = google_artifact_registry_repository.repo["my-maven-repo"].maven_config[0].version_policy == "SNAPSHOT"
    error_message = "version_policy must flow through to maven_config"
  }
}

# ── region accepts multi-region locations ────────────────────────────────────────

run "accepts_multi_region_us" {
  command = plan

  variables {
    region = "us"
  }
}

run "rejects_uppercase_region" {
  command         = plan
  expect_failures = [var.region]
  variables {
    region = "US-CENTRAL1"
  }
}

# ── repository_urls are built per format ─────────────────────────────────────────

run "repository_urls_are_per_format" {
  command = plan

  variables {
    region = "us-central1"
    repositories = {
      "docker-repo" = {
        description = "Docker repo"
        format      = "DOCKER"
      }
      "npm-repo" = {
        description = "NPM repo"
        format      = "NPM"
      }
      "generic-repo" = {
        description = "Generic repo (no registry host)"
        format      = "GENERIC"
      }
    }
  }

  assert {
    condition     = output.repository_urls["docker-repo"] == "us-central1-docker.pkg.dev/mock-project/docker-repo"
    error_message = "Docker repo URL must use the -docker.pkg.dev host"
  }

  assert {
    condition     = output.repository_urls["npm-repo"] == "us-central1-npm.pkg.dev/mock-project/npm-repo"
    error_message = "NPM repo URL must use the -npm.pkg.dev host"
  }

  assert {
    condition     = !contains(keys(output.repository_urls), "generic-repo")
    error_message = "GENERIC format has no registry host and must be omitted from repository_urls"
  }
}
