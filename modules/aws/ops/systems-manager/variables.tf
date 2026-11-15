# -----------------------------------------------------------------------------
# Session Manager preferences
# -----------------------------------------------------------------------------

variable "session_document_name" {
  description = "Name of the custom Session Manager preferences document. A custom name (not the reserved SSM-SessionManagerRunShell) keeps preferences under Terraform control per account."
  type        = string
  default     = "SessionManagerPreferences"

  validation {
    condition     = length(trimspace(var.session_document_name)) > 0
    error_message = "session_document_name must be a non-empty string."
  }
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket that receives Session Manager session logs."
  type        = string

  validation {
    condition     = length(trimspace(var.log_bucket_name)) > 0
    error_message = "log_bucket_name must be a non-empty S3 bucket name."
  }
}

variable "cloudwatch_log_group" {
  description = "CloudWatch Logs log group name that receives Session Manager session logs."
  type        = string
  default     = "/aws/ssm/session-logs"
}

variable "kms_key_id" {
  description = "KMS key ID or ARN used to encrypt Session Manager sessions and logs."
  type        = string

  validation {
    condition     = length(trimspace(var.kms_key_id)) > 0
    error_message = "kms_key_id must be a non-empty KMS key ID or ARN."
  }
}

# -----------------------------------------------------------------------------
# Patch baseline
# -----------------------------------------------------------------------------

variable "patch_baseline_name" {
  description = "Name of the SSM patch baseline."
  type        = string
  default     = "org-patch-baseline"

  validation {
    condition     = length(trimspace(var.patch_baseline_name)) > 0
    error_message = "patch_baseline_name must be a non-empty string."
  }
}

variable "patch_operating_systems" {
  description = "Operating systems that get a custom patch baseline, each set as the account default baseline for that OS. Supported: the Amazon Linux family, REDHAT_ENTERPRISE_LINUX, ROCKY_LINUX, ALMA_LINUX and WINDOWS. Amazon Linux 2 reached end of support on 2026-06-30: keep AMAZON_LINUX_2 here only while you still run it. Patch Manager uses the AWS predefined baseline for any OS not listed; the install association still patches those instances."
  type        = set(string)
  default     = ["AMAZON_LINUX_2023"]
  nullable    = false

  validation {
    condition = length(var.patch_operating_systems) > 0 && alltrue([for os in var.patch_operating_systems : contains([
      "AMAZON_LINUX", "AMAZON_LINUX_2", "AMAZON_LINUX_2023", "REDHAT_ENTERPRISE_LINUX", "ROCKY_LINUX", "ALMA_LINUX", "WINDOWS",
    ], os)])
    error_message = "patch_operating_systems must be a non-empty set of: AMAZON_LINUX, AMAZON_LINUX_2, AMAZON_LINUX_2023, REDHAT_ENTERPRISE_LINUX, ROCKY_LINUX, ALMA_LINUX, WINDOWS."
  }
}

variable "patch_operating_system" {
  description = "Single operating system for the patch baseline. Null (default) uses patch_operating_systems; a non-null value replaces that set with this one OS."
  type        = string
  default     = null
  deprecated  = "Use patch_operating_systems. patch_operating_system will be removed in a future major release."

  validation {
    condition = var.patch_operating_system == null || contains(
      ["AMAZON_LINUX", "AMAZON_LINUX_2", "AMAZON_LINUX_2023", "REDHAT_ENTERPRISE_LINUX", "ROCKY_LINUX", "ALMA_LINUX", "WINDOWS"],
      coalesce(var.patch_operating_system, "AMAZON_LINUX_2023")
    )
    error_message = "patch_operating_system must be null or one of: AMAZON_LINUX, AMAZON_LINUX_2, AMAZON_LINUX_2023, REDHAT_ENTERPRISE_LINUX, ROCKY_LINUX, ALMA_LINUX, WINDOWS."
  }
}

variable "patch_approve_after_days" {
  description = "Number of days to wait after a patch is released before auto-approving it."
  type        = number
  default     = 7

  validation {
    condition     = var.patch_approve_after_days >= 0 && var.patch_approve_after_days <= 360
    error_message = "patch_approve_after_days must be between 0 and 360."
  }
}

# -----------------------------------------------------------------------------
# Patch scan and install (AWS-RunPatchBaseline associations)
# -----------------------------------------------------------------------------

variable "enable_patch_install" {
  description = "Install approved patches on patch_install_schedule (AWS-RunPatchBaseline Operation=Install), on every SSM-managed instance in this account and region, or only on the instances that carry patch_install_target_tag. Instances reboot when a patch needs it (patch_reboot_option). False keeps the daily scan only."
  type        = bool
  default     = true
  nullable    = false
}

variable "patch_install_schedule" {
  description = "Cron expression (UTC) for the install association. The association runs only at this time, never at apply time (apply_only_at_cron_interval), so a rate() expression is rejected. Default: Sunday 03:00 UTC."
  type        = string
  default     = "cron(0 3 ? * SUN *)"
  nullable    = false

  validation {
    condition     = can(regex("^cron\\(.+\\)$", var.patch_install_schedule))
    error_message = "patch_install_schedule must be a cron(...) expression; the install association runs only at its cron time."
  }
}

variable "patch_reboot_option" {
  description = "RebootIfNeeded (default) or NoReboot. NoReboot leaves instances in a pending-reboot state that Patch Manager reports as non-compliant."
  type        = string
  default     = "RebootIfNeeded"
  nullable    = false

  validation {
    condition     = contains(["RebootIfNeeded", "NoReboot"], var.patch_reboot_option)
    error_message = "patch_reboot_option must be RebootIfNeeded or NoReboot."
  }
}

variable "patch_install_target_tag" {
  description = "Narrows the install association to the managed instances that carry this tag (key and value). Null (default) installs on every SSM-managed instance in this account and region. The daily scan always covers every managed instance."
  type = object({
    key   = string
    value = string
  })
  default = null

  validation {
    condition     = var.patch_install_target_tag == null || (length(trimspace(try(var.patch_install_target_tag.key, ""))) > 0 && length(trimspace(try(var.patch_install_target_tag.value, ""))) > 0)
    error_message = "patch_install_target_tag must be null or have a non-empty key and value."
  }
}

# -----------------------------------------------------------------------------
# Software inventory
# -----------------------------------------------------------------------------

variable "inventory_association_name" {
  description = "Name of the software-inventory State Manager association."
  type        = string
  default     = "org-inventory"

  validation {
    condition     = length(trimspace(var.inventory_association_name)) > 0
    error_message = "inventory_association_name must be a non-empty string."
  }
}

variable "inventory_schedule" {
  description = "Schedule expression (rate or cron) for the software-inventory association."
  type        = string
  default     = "rate(1 day)"

  validation {
    condition     = length(trimspace(var.inventory_schedule)) > 0
    error_message = "inventory_schedule must be a non-empty schedule expression."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
