/**
 * Copyright 2026 Ashes
 *
 * Cloud Run Job (v2) Module - Main Configuration
 *
 * Deploys a single Cloud Run v2 job: a run-to-completion container (batch,
 * migration, scheduled task) with no request serving and no URL. Secure by
 * default: the job runs as a dedicated service account, secret environment
 * variables come from Secret Manager, and deletion protection is on. Executions
 * are started by a caller holding roles/run.invoker (or run.developer) on the
 * job, e.g. a CI pipeline or a Cloud Scheduler trigger; this module creates none.
 */

resource "google_cloud_run_v2_job" "this" {
  project  = var.project_id
  location = var.location
  name     = var.name
  labels   = var.labels

  deletion_protection = var.enable_deletion_protection

  # Optional Binary Authorization: only attested images (or the project default
  # policy) may run. Null (default) leaves Binary Authorization off.
  dynamic "binary_authorization" {
    for_each = var.binary_authorization != null ? [var.binary_authorization] : []
    content {
      use_default              = binary_authorization.value.policy == null ? true : null
      policy                   = binary_authorization.value.policy
      breakglass_justification = binary_authorization.value.breakglass_justification
    }
  }

  template {
    task_count  = var.task_count
    parallelism = var.parallelism

    template {
      service_account = var.service_account_email
      timeout         = var.timeout
      max_retries     = var.max_retries

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

        # Secret-backed environment variables, resolved from Secret Manager at runtime.
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

  # Terraform owns the job CONFIGURATION; the delivery pipeline owns the IMAGE
  # (`gcloud run jobs deploy` replaces it and stamps client / client_version).
  # var.image is therefore the INITIAL image only.
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].template[0].containers[0].image,
    ]
  }
}
