# Variable validation tests for the artifact_registry module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  kms_key_name = "projects/mock-project/locations/us-central1/keyRings/test-ring/cryptoKeys/test-key"
  repositories = {}
}

# ── repositories format ────────────────────────────────────────────────────────

run "accepts_docker_format" {
  command = plan

  variables {
    repositories = {
      "my-docker-repo" = {
        description = "Docker repo"
        format      = "DOCKER"
      }
    }
  }
}

run "accepts_maven_format" {
  command = plan

  variables {
    repositories = {
      "my-maven-repo" = {
        description = "Maven repo"
        format      = "MAVEN"
      }
    }
  }
}

run "accepts_python_format" {
  command = plan

  variables {
    repositories = {
      "my-python-repo" = {
        description = "Python repo"
        format      = "PYTHON"
      }
    }
  }
}

run "accepts_npm_format" {
  command = plan

  variables {
    repositories = {
      "my-npm-repo" = {
        description = "NPM repo"
        format      = "NPM"
      }
    }
  }
}

run "rejects_invalid_format" {
  command = plan

  expect_failures = [var.repositories]

  variables {
    repositories = {
      "bad-repo" = {
        description = "Bad repo"
        format      = "INVALID_FORMAT"
      }
    }
  }
}

run "rejects_lowercase_format" {
  command = plan

  expect_failures = [var.repositories]

  variables {
    repositories = {
      "bad-repo" = {
        description = "Bad repo"
        format      = "docker"
      }
    }
  }
}

run "accepts_empty_repositories_map" {
  command = plan

  variables {
    repositories = {}
  }
}
