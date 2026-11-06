/**
 * Copyright 2026 Ashes
 *
 * App Services Stage - Outputs
 */

output "services" {
  description = "Per-service golden-path facts: Cloud Run URL and name, image repository path, runtime and deploy SA emails, and (when a database is declared) the Cloud SQL connection name and IAM DB user; Pub/Sub topic / subscription / dead-letter topic when pubsub is enabled; the ids of its alert policies."
  value = {
    for k, s in var.services : k => {
      service_name             = module.service[k].name
      url                      = module.service[k].uri
      image_repository         = local.image_repository[k]
      initial_image            = local.initial_image[k]
      runtime_service_account  = local.runtime_sa_email[k]
      deploy_service_account   = try(local.deploy_sa_email[k], null)
      database_connection_name = s.database == null ? null : module.database[k].connection_name
      database_iam_user        = s.database == null ? null : trimsuffix(local.runtime_sa_email[k], ".gserviceaccount.com")
      pubsub_topic             = try(local.pubsub_topic[k], null)
      pubsub_subscription      = try(local.pubsub_subscription[k], null)
      pubsub_dead_letter_topic = try(local.pubsub_dlq_topic[k], null)
      alert_policy_ids         = contains(keys(local.services_with_alerts), k) ? [google_monitoring_alert_policy.error_ratio[k].id, google_monitoring_alert_policy.latency_p99[k].id] : []
    }
  }
}

output "workload_identity_pool_name" {
  description = "Full resource name of the app-deploy Workload Identity pool, or null when enable_app_deploy_wif = false."
  value       = local.wif_pool_name
}

output "workload_identity_provider" {
  description = "Full resource name of the GitHub OIDC provider (the google-github-actions/auth `workload_identity_provider` input), or null until a service declares `github`."
  value       = local.wif_provider_name
}

output "github_actions" {
  description = "Per-service values to set as GitHub repository/environment variables for the delivery workflow (examples/app-delivery/cloud-run-delivery.example.yml): GCP_WIF_PROVIDER, GCP_DEPLOY_SA, GCP_PROJECT_ID, GCP_REGION, CLOUD_RUN_SERVICE, IMAGE_REPOSITORY."
  value = {
    for k, s in local.services_with_github : k => {
      GCP_WIF_PROVIDER  = local.wif_provider_name
      GCP_DEPLOY_SA     = local.deploy_sa_email[k]
      GCP_PROJECT_ID    = var.project_id
      GCP_REGION        = var.region
      CLOUD_RUN_SERVICE = k
      IMAGE_REPOSITORY  = local.image_repository[k]
    }
  }
}

output "gke_cluster_name" {
  description = "Name of the environment GKE Autopilot cluster, or null when disabled."
  value       = var.enable_gke_autopilot ? module.gke[0].name : null
}
