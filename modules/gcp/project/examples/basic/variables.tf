variable "project_id" {
  description = "Globally unique project ID to create."
  type        = string
  default     = "acme-dev-app-1a2b"
}

variable "folder_id" {
  description = "Numeric ID of the folder to create the project in."
  type        = string
  default     = "123456789012"
}

variable "billing_account" {
  description = "Billing account ID (XXXXXX-XXXXXX-XXXXXX)."
  type        = string
  default     = "ABCDEF-123456-ABCDEF"
}

variable "shared_vpc_host_project_id" {
  description = "Shared VPC host project to attach to (null = standalone project)."
  type        = string
  default     = null
}
