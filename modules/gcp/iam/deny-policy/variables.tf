variable "parent" {
  description = "URL-encoded attachment point for the deny policies — the full resource name with '/' encoded as '%2F', e.g. urlencode(\"cloudresourcemanager.googleapis.com/organizations/123456789\"). Org, folder, or project."
  type        = string

  validation {
    condition     = can(regex("cloudresourcemanager.googleapis.com%2F(organizations|folders|projects)%2F", var.parent))
    error_message = "parent must be a URL-encoded Cloud Resource Manager attachment point for an organization, folder, or project (build it with urlencode(...))."
  }
}

variable "deny_policies" {
  description = "IAM deny policies to create at the parent. Each has one or more rules; each rule denies a set of permissions for a set of principals, with optional exception principals/permissions and a CEL denial condition. Default [] = create nothing (inert)."
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
    condition     = length(var.deny_policies) == length(distinct([for p in var.deny_policies : p.name]))
    error_message = "deny_policies names must be unique."
  }

  validation {
    condition     = alltrue([for p in var.deny_policies : length(p.rules) > 0])
    error_message = "each deny policy must declare at least one rule."
  }
}
