# Example: two weekly VM Manager patch deployments for one project, each
# selected by label. Application VMs are patched early on Sunday (rebooting
# when the update needs it); database VMs are patched on Saturday and never
# rebooted automatically, so the database team can schedule the restart.
# (all_instances = true would patch, and reboot, the database VMs as well.)
#
# The osconfig.googleapis.com API and the OS Config agent on the VMs must be
# enabled for the jobs to run. Replace the placeholder project ID before use.
#
# Run `terraform init && terraform validate` here.

module "os_config" {
  source = "../../"

  project_id = "my-project-id"

  patch_deployments = {
    app-tier = {
      all_instances   = false
      instance_labels = { tier = "app" }
      reboot_config   = "DEFAULT"
      day_of_week     = "SUNDAY"
      start_time      = "03:00"
      time_zone       = "Europe/London"
      description     = "Weekly OS patching for application VMs"
    }
    db-tier = {
      all_instances   = false
      instance_labels = { tier = "database" }
      reboot_config   = "NEVER"
      day_of_week     = "SATURDAY"
      start_time      = "02:00"
      time_zone       = "Europe/London"
      description     = "Weekly OS patching for database VMs, no automatic reboot"
    }
  }
}
