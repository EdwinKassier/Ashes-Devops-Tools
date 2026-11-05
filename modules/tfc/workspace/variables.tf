variable "name" {
  description = "Workspace name, e.g. gcp-organization or aws-workload-prod."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*$", var.name))
    error_message = "Workspace name must start alphanumeric and contain only letters, digits, and -._ characters."
  }
}

variable "organization" {
  description = "Terraform Cloud organization that owns the workspace."
  type        = string
}

variable "description" {
  description = "Human-readable description of what the workspace deploys."
  type        = string
  default     = null
}

variable "working_directory" {
  description = "Repo-relative directory this workspace plans/applies from, e.g. envs/gcp/organization."
  type        = string
}

variable "execution_mode" {
  description = "TFC execution mode. 'remote' (default) runs plans/applies in TFC; 'agent'/'local' for special cases."
  type        = string
  default     = "remote"

  validation {
    condition     = contains(["remote", "local", "agent"], var.execution_mode)
    error_message = "execution_mode must be remote, local, or agent."
  }
}

variable "auto_apply" {
  description = "Apply automatically after a successful plan. Default false: foundational workspaces require manual apply approval."
  type        = bool
  default     = false
}

variable "terraform_version" {
  description = "Terraform version constraint for the workspace, e.g. ~> 1.9. Null uses the TFC default."
  type        = string
  default     = null
}

variable "tag_names" {
  description = "TFC workspace tags (e.g. cloud:gcp, layer:control-plane)."
  type        = list(string)
  default     = []
}

variable "queue_all_runs" {
  description = "Queue a run as soon as the workspace is created. Default false so the first apply is deliberate."
  type        = bool
  default     = false
}

variable "file_triggers_enabled" {
  description = "Trigger runs only when files under working_directory (or trigger_patterns) change."
  type        = bool
  default     = true
}

variable "trigger_patterns" {
  description = "Glob patterns that trigger a run (in addition to working_directory). Empty = working_directory only."
  type        = list(string)
  default     = []
}

variable "vcs_repo" {
  description = "Optional VCS connection: {identifier = \"org/repo\", branch = \"main\", oauth_token_id = \"ot-...\"}. Null = API/CLI-driven workspace."
  type = object({
    identifier     = string
    branch         = optional(string, "main")
    oauth_token_id = string
  })
  default = null
}

variable "variables" {
  description = "Workspace variables keyed by name: {value, category (terraform|env), hcl?, sensitive?, description?}."
  type = map(object({
    value       = string
    category    = string
    hcl         = optional(bool, false)
    sensitive   = optional(bool, false)
    description = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for v in values(var.variables) : contains(["terraform", "env"], v.category)])
    error_message = "Each variable's category must be 'terraform' or 'env'."
  }
}

variable "notifications" {
  description = <<-EOT
    Run notifications for this workspace, keyed by name. Default empty. Use this to
    alert on failed control-plane runs (audit M-ops): a failed apply on a
    foundational workspace is a control-plane event that should page someone.

    Per entry:
      destination_type  generic | slack | microsoft-teams | email.
      url               webhook URL (required for non-email destinations).
      token             optional HMAC token for a generic webhook.
      email_user_ids    TFC user IDs to email (email destination only).
      triggers          run events to notify on; default is a failed run plus a
                        run that needs attention (manual apply waiting).
      enabled           default true.
  EOT
  type = map(object({
    destination_type = string
    url              = optional(string)
    token            = optional(string)
    email_user_ids   = optional(list(string), [])
    triggers         = optional(list(string), ["run:errored", "run:needs_attention"])
    enabled          = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for n in values(var.notifications) : contains(["generic", "slack", "microsoft-teams", "email"], n.destination_type)])
    error_message = "Each notification destination_type must be generic, slack, microsoft-teams, or email."
  }

  validation {
    condition     = alltrue([for n in values(var.notifications) : n.destination_type == "email" || try(length(n.url) > 0, false)])
    error_message = "A non-email notification must set a webhook url."
  }

  validation {
    condition = alltrue([
      for n in values(var.notifications) : alltrue([
        for t in n.triggers : contains(["run:created", "run:planning", "run:needs_attention", "run:applying", "run:completed", "run:errored"], t)
      ])
    ])
    error_message = "Each trigger must be a valid TFC run trigger (run:created, run:planning, run:needs_attention, run:applying, run:completed, run:errored)."
  }
}
