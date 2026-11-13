# Example: deploy the unified compute dashboard to a workload project.
# The dashboard aggregates Cloud Run, Cloud Functions, and load-balancer metrics.

locals {
  project_id = "my-workload-project"
}

module "compute_dashboard" {
  source = "../../"

  project_id             = local.project_id
  dashboard_display_name = "API Service Compute"

  # Scorecard warning thresholds (dashboard colouring only; alerting is
  # monitoring/alert-policy).
  latency_threshold_ms         = 500 # p99 above 500 ms
  error_rate_threshold_percent = 0.5 # error rate above 0.5%

  # Set to false if the project uses only Cloud Run (Gen2) functions.
  include_gen1_functions = false
}
