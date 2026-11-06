# Module resources go here.
#
# Guidelines:
#   - One resource type per logical grouping; use locals for computed values.
#   - Add lifecycle { prevent_destroy = true } via a terraform_data guard (not
#     directly on the resource) when deletion protection is user-controlled.
#   - Use data sources only when required — prefer passing values as variables.
#   - checkov:skip annotations require a justification comment on the same line.
#   - Apply local.labels to EVERY resource that supports labels. Label keys are
#     lowercase kebab-case (managed-by, cost-center, ...) — never managed_by.
#
# EXAMPLE RESOURCE — replace with your module's real resource(s). Kept minimal
# and dependency-free so `terraform plan` succeeds under mock_provider with
# nothing but project_id set, giving tests/plan_assertions.tftest.hcl a real
# planned attribute to assert on.
locals {
  # Canonical labels merged under caller labels (caller wins on key collision).
  labels = merge({ "managed-by" = "terraform" }, var.labels)
}

resource "google_project_service" "example" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Labelled example — google_project_service takes no labels, so this shows the
# required local.labels wiring on a labelable resource. Replace or delete.
resource "google_compute_global_address" "example" {
  project = var.project_id
  name    = "module-template-example"

  labels = local.labels
}
