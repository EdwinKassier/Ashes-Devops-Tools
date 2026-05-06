# Example: create Docker and Python package Artifact Registry repositories.
# Replace locals with real values or remote state.

locals {
  project_id = "my-workload-project"
  region     = "us-central1"
}

module "registries" {
  source = "../../"

  project_id = local.project_id
  region     = local.region

  repositories = {
    "backend-images" = {
      description = "Docker images for backend services"
      format      = "DOCKER"
    }
    "python-packages" = {
      description    = "Internal Python packages"
      format         = "PYTHON"
      immutable_tags = false
    }
  }

  labels = {
    team       = "platform"
    managed-by = "terraform"
  }
}

output "registry_urls" {
  description = "Map of repository name to push/pull URL"
  value       = module.registries.repository_urls
}
