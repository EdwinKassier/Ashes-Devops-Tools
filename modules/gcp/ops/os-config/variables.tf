variable "project_id" {
  description = "Project ID where the OS Config (VM Manager) patch deployments are created."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 chars, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "patch_deployments" {
  description = <<-EOT
    VM Manager scheduled OS patch deployments, keyed by deployment id — the GCP
    parity counterpart to AWS Systems Manager patch baselines/Maintenance Windows.
    Each runs a recurring weekly patch job against the matched instances.
      - all_instances:  when true, patch every VM in the project (default true)
      - instance_labels: label map to target a subset (used when all_instances = false)
      - reboot_config:   DEFAULT | ALWAYS | NEVER
      - day_of_week + start HH:MM + time_zone: the recurring weekly window
  EOT
  type = map(object({
    all_instances   = optional(bool, true)
    instance_labels = optional(map(string), {})
    reboot_config   = optional(string, "DEFAULT")
    day_of_week     = optional(string, "SUNDAY")
    start_time      = optional(string, "03:00")
    time_zone       = optional(string, "Etc/UTC")
    description     = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for d in values(var.patch_deployments) : contains(["DEFAULT", "ALWAYS", "NEVER"], d.reboot_config)
    ])
    error_message = "each patch deployment reboot_config must be one of DEFAULT, ALWAYS, NEVER."
  }

  validation {
    condition = alltrue([
      for d in values(var.patch_deployments) :
      contains(["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"], d.day_of_week)
    ])
    error_message = "each patch deployment day_of_week must be a valid uppercase day name."
  }

  validation {
    condition = alltrue([
      for d in values(var.patch_deployments) : can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", d.start_time))
    ])
    error_message = "each patch deployment start_time must be a valid 24-hour HH:MM value."
  }
}
