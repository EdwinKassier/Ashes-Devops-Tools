variable "project_prefix" { type = string }
variable "default_region" { type = string }
variable "hub_project_id" { type = string }
variable "dns_project_id" { type = string }
variable "spoke_project_ids" { 
  type        = map(string)
  description = "Map of spoke project IDs to attach to Shared VPC"
}
variable "org_id" { type = string }
variable "folders" { 
  type        = map(any)
  description = "Map of folder objects to attach policies to"
}
