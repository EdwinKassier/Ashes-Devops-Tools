# Project Creation Facade
# Creates all environment projects based on the variable definition

locals {
  project_labels = {
    managed-by   = "terraform"
    owner        = "platform-team"
    organization = var.organization_name
  }
}

resource "google_project" "projects" {
  for_each = {
    for pair in flatten([
      for ou_k, ou in var.environments : [
        for proj_k, proj in ou.projects : {
          key  = "${ou_k}-${proj_k}"
          ou   = ou_k
          proj = proj
        }
      ]
    ]) : pair.key => pair
  }

  name = each.value.proj.name
  # Prevent redundant "dev-host-dev" naming. Use explicit name if provided, or prefix-env-name
  # Use the shared suffix to ensure ID stability
  project_id      = "${var.project_prefix}-${each.value.ou}-${each.value.proj.name}-${var.suffix}"
  billing_account = coalesce(each.value.proj.billing_account, var.default_billing_account)
  folder_id       = var.folders[each.value.ou].id

  labels = merge(
    local.project_labels,
    each.value.proj.labels,
    {
      environment = each.value.ou
    }
  )

  auto_create_network = false
}

# Enable required services for each project
locals {
  project_services = flatten([
    for proj_key, proj in google_project.projects : [
      for service in var.project_services : {
        project_id = proj.project_id
        service    = service
      }
    ]
  ])
}

resource "google_project_service" "project_services" {
  for_each = {
    for item in local.project_services : "${item.project_id}-${item.service}" => item
  }

  project = each.value.project_id
  service = each.value.service

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Monitoring for projects (Metrics Scope)
resource "google_monitoring_monitored_project" "projects" {
  for_each = google_project.projects

  metrics_scope = var.admin_project_id
  name          = each.value.project_id

  depends_on = [google_project_service.project_services]
}
