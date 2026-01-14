/**
 * Artifact Registry Module
 * Creates repositories for storing container images and language packages.
 * Supports Docker, Python, npm, Maven, Go, and Apt formats.
 */

resource "google_artifact_registry_repository" "repo" {
  for_each = var.repositories

  project       = var.project_id
  location      = var.region
  repository_id = each.key
  description   = each.value.description
  format        = each.value.format

  # Docker-specific configuration (only for DOCKER format)
  dynamic "docker_config" {
    for_each = each.value.format == "DOCKER" ? [1] : []
    content {
      immutable_tags = try(each.value.immutable_tags, false)
    }
  }

  # Maven-specific configuration (only for MAVEN format)
  dynamic "maven_config" {
    for_each = each.value.format == "MAVEN" ? [1] : []
    content {
      allow_snapshot_overwrites = try(each.value.allow_snapshot_overwrites, false)
      version_policy            = try(each.value.version_policy, "VERSION_POLICY_UNSPECIFIED")
    }
  }

  labels = merge(
    {
      "managed-by" = "terraform"
      "repository" = each.key
      "format"     = lower(each.value.format)
    },
    var.labels
  )
}