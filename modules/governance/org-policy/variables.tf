# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "parent" {
  description = "The parent resource where policies will be applied. Format: organizations/123, folders/456, or projects/789"
  type        = string

  validation {
    condition     = can(regex("^(organizations|folders|projects)/[0-9]+$", var.parent))
    error_message = "Parent must be in format: organizations/123, folders/456, or projects/789"
  }
}

# -----------------------------------------------------------------------------
# Policy Definitions
# -----------------------------------------------------------------------------

variable "boolean_policies" {
  description = "List of boolean organization policies to enforce or disable"
  type = list(object({
    constraint = string # e.g., "sql.restrictPublicIp", "compute.requireShieldedVm"
    enforce    = bool   # true = enforce the constraint, false = disable it
  }))
  default = []

  # Common boolean constraints:
  # - sql.restrictPublicIp              : Block public IP on Cloud SQL instances
  # - storage.uniformBucketLevelAccess  : Require uniform IAM access on buckets
  # - storage.publicAccessPrevention    : Prevent public access to Cloud Storage
  # - iam.disableServiceAccountKeyCreation : Block SA key creation
  # - compute.requireShieldedVm         : Require Shielded VM for all instances
  # - compute.disableSerialPortAccess   : Disable serial port access
  # - compute.requireOsLogin            : Require OS Login for SSH
}

variable "list_policies" {
  description = "List of list-type organization policies with allowed/denied values"
  type = list(object({
    constraint     = string       # e.g., "gcp.resourceLocations"
    allow_all      = bool         # Allow all values (overrides allowed_values)
    deny_all       = bool         # Deny all values (overrides denied_values)
    allowed_values = list(string) # Specific values to allow
    denied_values  = list(string) # Specific values to deny
  }))
  default = []

  # Common list constraints:
  # - gcp.resourceLocations           : Restrict regions (e.g., ["in:us-locations"])
  # - gcp.restrictNonCmekServices     : Require CMEK for services (deny = service names)
  # - gcp.restrictCmekCryptoKeyProjects : Limit KMS key source projects
  # - compute.vmExternalIpAccess      : Control which VMs can have external IPs
  # - compute.trustedImageProjects    : Restrict allowed VM image projects
}

# -----------------------------------------------------------------------------
# Optional: Resource Labels
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply for tracking and organization"
  type        = map(string)
  default     = {}
}

variable "custom_constraints" {
  description = "List of custom organization policy constraints to create"
  type = list(object({
    name           = string       # Unique name, e.g., "custom.disableGkeAutoUpgrade"
    display_name   = string       # Human readable name
    description    = string       # Description of the constraint
    action_type    = string       # ALLOW or DENY
    condition      = string       # CEL condition, e.g., "resource.management.autoUpgrade == true"
    method_types   = list(string) # Operations to restrict: CREATE, UPDATE, DELETE
    resource_types = list(string) # Resources to restrict: e.g. ["container.googleapis.com/NodePool"]
  }))
  default = []
}
