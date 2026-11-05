/**
 * Copyright 2023 Ashes
 *
 * Cloud Run (v2) Module - Main Configuration
 *
 * Deploys a single Cloud Run v2 service — the serverless application runtime.
 * Secure by default: the service runs as a dedicated service account, is reachable
 * only via an internal load balancer, and stays private unless unauthenticated
 * access is explicitly enabled. Secret environment variables are sourced from
 * Secret Manager, never passed as plaintext.
 */

resource "google_cloud_run_v2_service" "this" {
  project  = var.project_id
  location = var.location
  name     = var.name
  ingress  = var.ingress
  labels   = var.labels

  # Maps the user-controlled flag directly onto the provider's deletion guard.
  deletion_protection = var.enable_deletion_protection

  template {
    service_account                  = var.service_account_email
    timeout                          = var.timeout
    max_instance_request_concurrency = var.concurrency

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    dynamic "vpc_access" {
      for_each = var.vpc_access != null ? [var.vpc_access] : []
      content {
        connector = vpc_access.value.connector
        egress    = vpc_access.value.egress

        dynamic "network_interfaces" {
          for_each = vpc_access.value.network_interfaces != null ? [vpc_access.value.network_interfaces] : []
          content {
            network    = network_interfaces.value.network
            subnetwork = network_interfaces.value.subnetwork
            tags       = network_interfaces.value.tags
          }
        }
      }
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      # Plain environment variables.
      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret-backed environment variables — resolved from Secret Manager at runtime.
      dynamic "env" {
        for_each = { for s in var.secret_env_vars : s.name => s }
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }
    }
  }
}

# Public (unauthenticated) invoker binding — created only when explicitly enabled.
resource "google_cloud_run_v2_service_iam_member" "unauthenticated" {
  count = var.enable_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
