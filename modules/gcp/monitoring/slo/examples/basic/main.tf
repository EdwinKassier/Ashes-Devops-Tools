# Example: a 99.9% availability SLO over a rolling 28 days for an existing
# Cloud Run service, with a burn-rate alert that pages when the error budget
# burns at 10x the sustainable rate over the last hour.
#
# The example declares the monitored service for the Cloud Run service (the
# same pattern gcp/stages/app-services uses) and attaches the SLO to it. The
# notification channel must already exist. Replace the placeholder values
# before use.
#
# Run `terraform init && terraform validate` here.

locals {
  project_id = "my-project-id"
  region     = "europe-west2"
  service    = "orders-api"
}

resource "google_monitoring_service" "orders_api" {
  project      = local.project_id
  service_id   = "cloud-run-${local.service}"
  display_name = "prod/${local.service}"

  basic_service {
    service_type = "CLOUD_RUN"
    service_labels = {
      service_name = local.service
      location     = local.region
    }
  }
}

module "slo" {
  source = "../../"

  project_id   = local.project_id
  service_id   = google_monitoring_service.orders_api.service_id
  slo_id       = "${local.service}-availability"
  display_name = "prod/${local.service} 99.9% availability"

  sli_type            = "availability"
  goal                = 0.999
  rolling_period_days = 28

  enable_burn_rate_alert = true
  burn_rate_threshold    = 10
  burn_rate_lookback     = "3600s"
  notification_channels  = ["projects/my-project-id/notificationChannels/1234567890"]

  labels = {
    service = local.service
  }
}
