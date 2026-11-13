variable "terraform_admin_email" {
  description = "Service account the google providers impersonate (for example terraform@my-seed-project.iam.gserviceaccount.com). Null uses the ambient credentials (ADC or HCP Terraform dynamic credentials). policies/opa/no_plan_time_code_execution.rego allows impersonate_service_account only from this variable, with a null default."
  type        = string
  default     = null
}
