variable "org_id" {
  description = "Numeric GCP organization ID. The deny policies attach to this organization node."
  type        = string

  validation {
    condition     = length(var.org_id) > 0
    error_message = "org_id must be set."
  }
}

variable "enable_admin_containment" {
  description = "Create the admin-containment IAM deny policy (contain-admin-identity). For all principals except containment_exempt_principals (break-glass) it blocks, org-wide, sink update/delete, exclusion changes, log-bucket delete and VPC-SC perimeter, access-level and access-policy mutation. Scoped by the containment/protected tag to the audit store, it also blocks bucket delete/update/IAM change/untag, object delete, key-version destroy/disable and key and keyring IAM change. Once on, any change to a sink, exclusion or perimeter must be applied by break-glass. Default false."
  type        = bool
  default     = false
}

variable "containment_exempt_principals" {
  description = "Break-glass principals exempt from the admin-containment deny policy, as IAM v2 principal identifiers (e.g. principalSet://goog/group/break-glass@acme.com). Required (non-empty) when enable_admin_containment is true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_admin_containment || length(var.containment_exempt_principals) > 0
    error_message = "containment_exempt_principals must be non-empty when enable_admin_containment is true, or the deny applies to everyone including break-glass."
  }

  validation {
    condition     = alltrue([for p in var.containment_exempt_principals : can(regex("^principal(Set)?://", p))])
    error_message = "containment_exempt_principals entries must be IAM v2 principal identifiers (principal://... or principalSet://...), e.g. principalSet://goog/group/break-glass@acme.com."
  }

  validation {
    condition     = !anytrue([for p in var.containment_exempt_principals : can(regex("(?i)(replace-me|your-domain|example\\.(com|org|net)|\\.invalid$|changeme)", p))])
    error_message = "containment_exempt_principals still contains a placeholder (REPLACE-ME / your-domain / example.com / .invalid). Set your real break-glass group before enabling admin containment."
  }
}

variable "containment_tag_key_id" {
  description = "ID of the containment tag key that marks the audit store (created and bound by the organization stage), as tagKeys/<n> or the bare <n>. Required when enable_admin_containment is true."
  type        = string
  default     = null
}

variable "containment_tag_value_id" {
  description = "ID of the containment/protected tag value, as tagValues/<n> or the bare <n>. Required when enable_admin_containment is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_admin_containment || (var.containment_tag_key_id != null && var.containment_tag_value_id != null)
    error_message = "enable_admin_containment needs containment_tag_key_id and containment_tag_value_id: without them the audit-store rule matches nothing. Apply gcp-organization with containment on first; it creates the containment/protected tag."
  }
}

variable "enable_principal_access_boundary" {
  description = "The organization stage binds a principal access boundary to the automation service accounts. With containment on, its update, delete and unbind are then denied to all but break-glass. Keep it in step with the gcp-organization enable_principal_access_boundary input. Default false."
  type        = bool
  default     = false
}

variable "iam_deny_policies" {
  description = "Extra IAM deny policies at the org node, created next to the containment policy: a coarse, allow-independent backstop that blocks specific permissions for specific principals regardless of the roles they hold. Default [] = none."
  type = list(object({
    name         = string
    display_name = optional(string)
    rules = list(object({
      description           = optional(string)
      denied_principals     = list(string)
      denied_permissions    = list(string)
      exception_principals  = optional(list(string), [])
      exception_permissions = optional(list(string), [])
      denial_condition = optional(object({
        expression  = string
        title       = optional(string)
        description = optional(string)
      }))
    }))
  }))
  default = []

  validation {
    condition     = !var.enable_admin_containment || !contains([for p in var.iam_deny_policies : p.name], "contain-admin-identity")
    error_message = "iam_deny_policies must not reuse the name contain-admin-identity: the admin-containment policy owns it."
  }
}

variable "create_deny_policies" {
  description = "Create the deny policies at the org node. false = only render them (outputs deny_policies and deny_policy_specs) for a caller that applies them itself, as the organization stage does in its legacy guardrail_owner_mode = \"organization\". Default true."
  type        = bool
  default     = true
}
