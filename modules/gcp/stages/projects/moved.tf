# State migration for the move from a raw google_project -> the shared
# project primitive, modules/gcp/project).
#
# 1. PROJECTS — google_project.projects["<key>"] now lives at
#    module.project["<key>"].google_project.this. A `moved` block cannot iterate
#    (no for_each) and this stage does not know its caller's keys, so the move is
#    done by the CALLER: envs/gcp/projects/moved.tf moves the built-in
#    shared-hub / shared-dns projects, and every "<env>-host" project is moved with
#    the `terraform state mv` loop in this stage's README ("Migrating state").
#    If a project is NOT moved, the plan shows destroy + create; the destroy fails
#    on deletion_policy = PREVENT and the create would 409 — nothing is lost, but
#    the apply cannot succeed until the state is moved.
#
# 2. SERVICES — the old google_project_service.project_services was keyed
#    "<project_id>-<api>" (unmappable to the module's "<api>" keys without
#    for_each). Both old and new use disable_on_destroy = false, so the old
#    entries are simply FORGOTTEN (never disabled) and the module re-adopts the
#    already-enabled APIs on the next apply (enabling an enabled API is a no-op).
removed {
  from = google_project_service.project_services

  lifecycle {
    destroy = false
  }
}
