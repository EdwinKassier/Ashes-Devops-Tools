variable "project_id" {
  description = "Project that holds the alert policies and notification channels. Use the project that receives the aggregated org Admin Activity audit logs, so the watch filters have logs to match."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

variable "enable" {
  description = "Master gate. When false the module creates nothing (no channels, no alert policies)."
  type        = bool
  default     = true
}

variable "notification_email_addresses" {
  description = "Email addresses to notify. Each becomes an email notification channel attached to every alert."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.notification_email_addresses : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every notification email must be a valid address."
  }
}

variable "notification_webhook_urls" {
  description = "Map of label to webhook URL (e.g. Slack) to notify, in addition to email. Marked sensitive because URLs can embed tokens."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "extra_notification_channel_ids" {
  description = "IDs of pre-existing notification channels to attach to every alert, in addition to the channels this module creates."
  type        = list(string)
  default     = []
}

variable "watches" {
  description = <<-EOT
    Guardrail-mutation watches, keyed by a short name. Each creates one log-match
    alert policy: a matching Admin Activity audit-log entry fires the alert. The
    default set covers the landing zone's control plane (org policy, org/folder
    IAM, VPC Service Controls, audit config, and logging sinks). Admins have full
    control: remove entries to stop watching them, change a filter, or add custom
    watches. Each entry sets display_name, filter, optional severity (defaults to
    WARNING), and optional documentation.
  EOT
  type = map(object({
    display_name  = string
    filter        = string
    severity      = optional(string, "WARNING")
    documentation = optional(string)
  }))
  default = {
    org_policy_change = {
      display_name = "Organization policy changed"
      filter       = "protoPayload.serviceName=\"orgpolicy.googleapis.com\" AND protoPayload.methodName:(\"SetOrgPolicy\" OR \"CreatePolicy\" OR \"UpdatePolicy\" OR \"DeletePolicy\")"
      severity     = "ERROR"
    }
    org_iam_change = {
      display_name = "Organization or folder IAM policy changed"
      filter       = "protoPayload.methodName=\"SetIamPolicy\" AND (resource.type=\"organization\" OR resource.type=\"folder\")"
      severity     = "ERROR"
    }
    vpc_sc_change = {
      display_name = "VPC Service Controls perimeter changed"
      filter       = "protoPayload.serviceName=\"accesscontextmanager.googleapis.com\" AND protoPayload.methodName:(\"Create\" OR \"Update\" OR \"Replace\" OR \"Delete\")"
      severity     = "ERROR"
    }
    audit_config_change = {
      display_name = "Audit logging configuration changed"
      filter       = "protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*"
      severity     = "ERROR"
    }
    log_sink_change = {
      display_name = "Logging sink or exclusion created, updated or deleted"
      filter       = "protoPayload.serviceName=\"logging.googleapis.com\" AND protoPayload.methodName:(\"CreateSink\" OR \"DeleteSink\" OR \"UpdateSink\" OR \"CreateExclusion\" OR \"UpdateExclusion\" OR \"DeleteExclusion\")"
      severity     = "ERROR"
    }
    custom_role_change = {
      display_name = "Custom IAM role created, updated or deleted"
      filter       = "protoPayload.serviceName=\"iam.googleapis.com\" AND protoPayload.methodName:(\"CreateRole\" OR \"UpdateRole\" OR \"DeleteRole\" OR \"UndeleteRole\")"
      severity     = "WARNING"
    }
    deny_policy_change = {
      # iam.denypolicies.* cannot itself be denied by an IAM deny policy (not in
      # the supported-permissions list), so detection is the control here.
      display_name = "IAM deny policy changed"
      filter       = "protoPayload.serviceName=\"iam.googleapis.com\" AND protoPayload.methodName:(\"Policies.CreatePolicy\" OR \"Policies.UpdatePolicy\" OR \"Policies.DeletePolicy\")"
      severity     = "ERROR"
    }
    kms_key_destroy = {
      display_name = "KMS key version destroy scheduled"
      filter       = "protoPayload.serviceName=\"cloudkms.googleapis.com\" AND protoPayload.methodName=\"DestroyCryptoKeyVersion\""
      severity     = "ERROR"
    }
  }

  validation {
    condition     = alltrue([for w in values(var.watches) : contains(["ERROR", "WARNING", "CRITICAL"], try(w.severity, "WARNING"))])
    error_message = "Each watch severity must be one of ERROR, WARNING, or CRITICAL."
  }

  validation {
    condition     = alltrue([for w in values(var.watches) : length(trimspace(w.filter)) > 0 && length(trimspace(w.display_name)) > 0])
    error_message = "Each watch must set a non-empty filter and display_name."
  }
}

variable "enable_log_export_error_alert" {
  description = "Also alert when the audit-log export sink reports delivery errors (a stalled audit pipeline). Requires the logging_sink metric to exist in project_id."
  type        = bool
  default     = true
}

variable "notification_rate_limit_seconds" {
  description = "Minimum seconds between notifications for a single watch, so a burst of matching entries does not flood the channel."
  type        = number
  default     = 300

  validation {
    condition     = var.notification_rate_limit_seconds >= 0 && var.notification_rate_limit_seconds <= 86400
    error_message = "notification_rate_limit_seconds must be between 0 and 86400."
  }
}

variable "alert_display_name_prefix" {
  description = "Prefix prepended to every alert policy display name, e.g. \"Control plane: \"."
  type        = string
  default     = "Control plane: "
}

variable "labels" {
  description = "User labels applied to the notification channels."
  type        = map(string)
  default     = {}
}

variable "break_glass_principal_emails" {
  description = "Emails of break-glass principals (users or service accounts). When non-empty, adds a CRITICAL watch that fires on ANY Admin Activity performed by one of them, so break-glass use is always noticed. Default [] = no break-glass watch."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.break_glass_principal_emails : can(regex("^[^@\\s\"]+@[^@\\s\"]+\\.[^@\\s\"]+$", e))])
    error_message = "Every break_glass_principal_emails entry must be a plain email address."
  }
}

variable "org_id" {
  description = <<-EOT
    Numeric organization ID. When set, the module creates an aggregated org log sink
    that routes the org's Admin Activity and Policy audit logs (including org- and
    folder-level entries, which are never stored in any project) into project_id, so the
    log-match watches can see them. Leave null only if logs are already routed into
    project_id by other means.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.org_id == null || can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only) or null."
  }
}

variable "org_log_route_sink_name" {
  description = "Name of the aggregated org sink created when org_id is set."
  type        = string
  default     = "org-control-plane-to-monitoring"
}
