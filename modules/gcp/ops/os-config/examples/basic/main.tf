# Example: two weekly VM Manager patch deployments for one project. Every VM
# is patched early on Sunday (rebooting when the update needs it); database
# VMs, selected by label, are patched on Saturday and never rebooted
# automatically, so the database team can schedule the restart.
#
# The osconfig.googleapis.com API and the OS Config agent on the VMs must be
# enabled for the jobs to run. Replace the placeholder project ID before use.
#
# Run `terraform init && terraform validate` here.

module "os_config" {
  source = "../../"

  project_id = "my-project-id"

  patch_deployments = {
    weekly-all = {
      all_instances = true
      reboot_config = "DEFAULT"
      day_of_week   = "SUNDAY"
      start_time    = "03:00"
      time_zone     = "Europe/London"
      description   = "Weekly OS patching for every VM"
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
