variable "project_prefix" {
  description = "Short prefix used to namespace the service project (e.g. 'acme')"
  type        = string
  default     = "example"
}

variable "environment" {
  description = "Environment label applied to resource names and labels (e.g. 'dev', 'prod')"
  type        = string
  default     = "dev"
}
