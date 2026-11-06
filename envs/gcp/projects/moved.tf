# Audit Modularity-H: stages/projects now creates projects through the shared
# project primitive (modules/gcp/project). The built-in shared-services projects
# have static keys, so they are moved here; per-environment "<env>-host" projects
# are keyed by var.environments and must be moved with the `terraform state mv`
# loop documented in modules/gcp/stages/projects/README.md ("Migrating state").
# A moved block whose `from` is absent from state (greenfield) is a no-op.

moved {
  from = module.projects.google_project.projects["shared-hub"]
  to   = module.projects.module.project["shared-hub"].google_project.this
}

moved {
  from = module.projects.google_project.projects["shared-dns"]
  to   = module.projects.module.project["shared-dns"].google_project.this
}
