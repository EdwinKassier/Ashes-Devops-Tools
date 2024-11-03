resource "google_artifact_registry_repository" "ashes-flask-repo" {
  location      = "us-central1"
  repository_id = "ashes-flask-repo"
  description   = "Artifact registry for flask images"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }
}

resource "google_artifact_registry_repository" "ashes-django-repo" {
  location      = "us-central1"
  repository_id = "ashes-django-repo"
  description   = "Artifact registry for django images"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }
}

resource "google_artifact_registry_repository" "ashes-fastapi-repo" {
  location      = "us-central1"
  repository_id = "ashes-fastapi-repo"
  description   = "Artifact registry for fastapi images"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }
}

resource "google_artifact_registry_repository" "ashes-express-repo" {
  location      = "us-central1"
  repository_id = "ashes-express-repo"
  description   = "Artifact registry for express images"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }
}

resource "google_artifact_registry_repository" "ashes-hermes-repo" {
  location      = "us-central1"
  repository_id = "ashes-hermes-repo"
  description   = "Artifact registry for hermes images"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }
}