resource "google_artifact_registry_repository" "repo" {
  for_each = var.repositories

  project       = var.project_id
  location      = var.region
  repository_id = each.key
  description   = each.value.description
  format        = each.value.format

  docker_config {
    immutable_tags = each.value.immutable_tags
  }

  labels = merge(
    {
      "managed-by"  = "terraform"
      "repository"  = each.key
    },
    var.labels
  )
}