/**
 * Artifact Registry Module
 * Creates repositories for storing container images and language packages.
 * Supports Docker, Python, npm, Maven, Go, and Apt formats.
 */

locals {
  # Formats that expose a package-manager registry host. Others (APT/YUM/GOOGET/KFP/GENERIC)
  # have no such host and are omitted from the repository_urls map.
  ar_hosts = {
    DOCKER = "docker"
    MAVEN  = "maven"
    NPM    = "npm"
    PYTHON = "python"
  }
}

resource "google_artifact_registry_repository" "repo" {
  for_each = var.repositories

  project       = var.project_id
  location      = var.region
  repository_id = each.key
  description   = each.value.description
  format        = each.value.format
  kms_key_name  = var.kms_key_name

  # Cleanup policies bound registry growth (and cost). In dry-run mode Artifact
  # Registry only logs what it would delete — validate before enforcing.
  cleanup_policy_dry_run = length(each.value.cleanup_policies) > 0 ? each.value.cleanup_policy_dry_run : null

  dynamic "cleanup_policies" {
    for_each = each.value.cleanup_policies
    content {
      id     = cleanup_policies.key
      action = cleanup_policies.value.action

      dynamic "condition" {
        for_each = cleanup_policies.value.condition != null ? [cleanup_policies.value.condition] : []
        content {
          tag_state             = condition.value.tag_state
          tag_prefixes          = condition.value.tag_prefixes
          version_name_prefixes = condition.value.version_name_prefixes
          package_name_prefixes = condition.value.package_name_prefixes
          older_than            = condition.value.older_than
          newer_than            = condition.value.newer_than
        }
      }

      dynamic "most_recent_versions" {
        for_each = cleanup_policies.value.most_recent_versions != null ? [cleanup_policies.value.most_recent_versions] : []
        content {
          package_name_prefixes = most_recent_versions.value.package_name_prefixes
          keep_count            = most_recent_versions.value.keep_count
        }
      }
    }
  }

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
