# State migration: upstream terraform-google-modules/project-factory (~> 18.2,
# resolved 18.4.0) -> the shared project primitive (audit Modularity-H).
#
# Internal upstream addresses (module "project" -> module "project-factory" =
# ./modules/core_project_factory) were read from the resolved module source in
# envs/gcp/workload/.terraform/modules/service_team.project. Every resource the
# old call actually instantiated is either moved or explicitly forgotten, so the
# first plan after the upgrade replaces nothing.

moved {
  from = module.project.module.project-factory.google_project.main
  to   = module.project.google_project.this
}

moved {
  from = module.project.module.project-factory.random_id.random_project_id_suffix
  to   = random_id.project_suffix
}

moved {
  from = module.project.module.project-factory.google_service_account.default_service_account[0]
  to   = google_service_account.project[0]
}

moved {
  from = module.project.module.project-factory.google_project_default_service_accounts.default_service_accounts[0]
  to   = google_project_default_service_accounts.this[0]
}

moved {
  from = google_compute_shared_vpc_service_project.attachment[0]
  to   = module.project.google_compute_shared_vpc_service_project.this[0]
}

# APIs: the upstream module enabled them with disable_on_destroy = TRUE. Moving
# them would carry that flag into a destroy for any API no longer requested
# (notably container.googleapis.com, now opt-in via enable_gke) and DISABLE it on
# a live project. Instead the old entries are forgotten — never disabled — and
# the primitive re-adopts the still-requested APIs (enabling an enabled API is a
# no-op) with disable_on_destroy = false. An API dropped from the list (e.g.
# container) simply stays enabled in GCP, unmanaged.
removed {
  from = module.project.module.project-factory.module.project_services.google_project_service.project_services

  lifecycle {
    destroy = false
  }
}
