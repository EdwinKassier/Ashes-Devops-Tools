/**
 * Copyright 2026 Ashes
 *
 * App Services Stage - Outputs
 */

output "services" {
  description = "Per-service golden-path facts: runtime, Cloud Run service name and URL (null for a job) or job name (null for a service), image repository path, runtime and deploy SA emails, and (when a database is declared) the Cloud SQL connection name, IAM DB user and availability type (REGIONAL or ZONAL); Pub/Sub topic / subscription / dead-letter topic when pubsub is enabled; the ids of its alert policies and its SLO name (null when none is declared)."
  value = {
    for k, s in var.services : k => {
      runtime                  = s.runtime
      service_name             = s.runtime == "cloud-run" ? module.service[k].name : null
      url                      = s.runtime == "cloud-run" ? module.service[k].uri : null
      job_name                 = s.runtime == "cloud-run-job" ? module.job[k].name : null
      image_repository         = local.image_repository[k]
      initial_image            = local.initial_image[k]
      runtime_service_account  = local.runtime_sa_email[k]
      deploy_service_account   = try(local.deploy_sa_email[k], null)
      database_connection_name = s.database == null ? null : module.database[k].connection_name
      database_iam_user        = s.database == null ? null : trimsuffix(local.runtime_sa_email[k], ".gserviceaccount.com")
      database_availability    = s.database == null ? null : module.database[k].availability_type
      pubsub_topic             = try(local.pubsub_topic[k], null)
      pubsub_subscription      = try(local.pubsub_subscription[k], null)
      pubsub_dead_letter_topic = try(local.pubsub_dlq_topic[k], null)
      alert_policy_ids         = contains(keys(local.services_with_alerts), k) ? [google_monitoring_alert_policy.error_ratio[k].id, google_monitoring_alert_policy.latency_p99[k].id] : []
      slo_name                 = contains(keys(local.services_with_slo), k) ? module.slo[k].slo_name : null
    }
  }
}

output "urls" {
  description = "Cloud Run service URL per service key (Cloud Run services only; jobs have no URL)."
  value       = { for k, s in local.cloud_run_services : k => module.service[k].uri }
}

output "runtime_service_account_emails" {
  description = "Runtime service account email per service key."
  value       = local.runtime_sa_email
}

output "image_repositories" {
  description = "Artifact Registry image repository path (<region>-docker.pkg.dev/<project>/<service>/<service>) per service key."
  value       = local.image_repository
}

output "sql_connection_names" {
  description = "Cloud SQL instance connection name (<project>:<region>:<instance>) per service key that declares a database."
  value       = { for k, s in local.services_with_db : k => module.database[k].connection_name }
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
  description = "Per-service values to set as GitHub repository/environment variables for the delivery workflow (examples/app-delivery/cloud-run-delivery.example.yml): GCP_WIF_PROVIDER, GCP_DEPLOY_SA, GCP_PROJECT_ID, GCP_REGION, CLOUD_RUN_SERVICE (null for a job), CLOUD_RUN_JOB (null for a service), IMAGE_REPOSITORY."
  value = {
    for k, s in local.services_with_github : k => {
      GCP_WIF_PROVIDER  = local.wif_provider_name
      GCP_DEPLOY_SA     = local.deploy_sa_email[k]
      GCP_PROJECT_ID    = local.service_project[k]
      GCP_REGION        = var.region
      CLOUD_RUN_SERVICE = s.runtime == "cloud-run" ? k : null
      CLOUD_RUN_JOB     = s.runtime == "cloud-run-job" ? k : null
      IMAGE_REPOSITORY  = local.image_repository[k]
    }
  }
}

output "gke_cluster_name" {
  description = "Name of the environment GKE Autopilot cluster, or null when disabled."
  value       = var.enable_gke_autopilot ? module.gke[0].name : null
}
