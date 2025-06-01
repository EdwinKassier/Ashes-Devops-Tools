variable "project_id" {
  description = "The ID of the project where the custom role will be created"
  type        = string
}

variable "role_id" {
  description = "The camelCaseRoleId for the custom role"
  type        = string
}

variable "title" {
  description = "A human-readable title for the custom role"
  type        = string
}

variable "description" {
  description = "A description of the custom role"
  type        = string
}

variable "permissions" {
  description = "The list of permissions that the custom role will grant"
  type        = list(string)
}

variable "stage" {
  description = "The current launch stage of the role (ALPHA, BETA, GA, DEPRECATED, DISABLED, EAP)"
  type        = string
  default     = "GA"
  validation {
    condition     = contains(["ALPHA", "BETA", "GA", "DEPRECATED", "DISABLED", "EAP"], var.stage)
    error_message = "Stage must be one of: ALPHA, BETA, GA, DEPRECATED, DISABLED, EAP."
  }
} 