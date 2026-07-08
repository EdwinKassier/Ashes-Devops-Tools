# Module resources go here.
#
# Guidelines:
#   - One resource type per logical grouping; use locals for computed values.
#   - Add lifecycle { prevent_destroy = true } via a terraform_data guard (not
#     directly on the resource) when deletion protection is user-controlled.
#   - Use data sources only when required — prefer passing values as variables.
#   - checkov:skip annotations require a justification comment on the same line.
#
# EXAMPLE RESOURCE — replace with your module's real resource(s). Kept minimal
# and dependency-free so `terraform plan` succeeds under mock_provider with
# nothing but project_id set, giving tests/plan_assertions.tftest.hcl a real
# planned attribute to assert on.
resource "google_project_service" "example" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}
