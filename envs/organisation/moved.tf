# State Migration Mappings
# These blocks ensure Terraform treats the refactor as a renaming operation
# rather than a destroy/create operation.

# Bootstrap Module Mappings
moved {
  from = google_project.admin_project
  to   = module.bootstrap.google_project.admin_project
}

moved {
  from = random_id.suffix
  to   = module.bootstrap.random_id.suffix
}

moved {
  from = google_project_service.admin_project_services
  to   = module.bootstrap.google_project_service.admin_project_services
}

moved {
  from = module.terraform_admin_sa
  to   = module.bootstrap.module.terraform_admin_sa
}

moved {
  from = module.gh_oidc
  to   = module.bootstrap.module.gh_oidc
}

# Organization Module Mappings
moved {
  from = module.organization
  to   = module.organization.module.organization
}

moved {
  from = module.tags
  to   = module.organization.module.tags
}

moved {
  from = module.org_policies
  to   = module.organization.module.org_policies
}

moved {
  from = module.prod_folder_policies
  to   = module.organization.module.prod_folder_policies
}

moved {
  from = module.audit_logs
  to   = module.organization.module.audit_logs
}

moved {
  from = module.scc_notifications
  to   = module.organization.module.scc_notifications
}

moved {
  from = google_essential_contacts_contact.security
  to   = module.organization.google_essential_contacts_contact.security
}

moved {
  from = google_essential_contacts_contact.billing
  to   = module.organization.google_essential_contacts_contact.billing
}

moved {
  from = module.org_budget
  to   = module.organization.module.org_budget
}

moved {
  from = google_bigquery_dataset.billing_export
  to   = module.organization.google_bigquery_dataset.billing_export
}

# Projects Module Mappings
moved {
  from = google_project.projects
  to   = module.projects.google_project.projects
}

moved {
  from = google_project_service.project_services
  to   = module.projects.google_project_service.project_services
}

moved {
  from = google_monitoring_monitored_project.projects
  to   = module.projects.google_monitoring_monitored_project.projects
}

# Network Hub Module Mappings
moved {
  from = module.hub_network
  to   = module.network_hub.module.hub_network
}

moved {
  from = module.dns_hub_network
  to   = module.network_hub.module.dns_hub_network
}

moved {
  from = module.dns_hub_zone
  to   = module.network_hub.module.dns_hub_zone
}
