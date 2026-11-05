variable "tfc_organization" {
  description = "Terraform Cloud organization that owns all the managed workspaces."
  type        = string
}

variable "environments" {
  description = "Application environments to create per-env workload workspaces for (gcp-workload-<env>, and aws-workload-<env> when enable_aws). Only the keys are used. Keep in sync with the cloud roots' environments map."
  type        = map(object({}))
  default     = {}
}

variable "enable_aws" {
  description = "Also declare the AWS control-plane and per-env workload workspaces. Default false keeps this GCP-only; set true for an AWS or multi-cloud estate."
  type        = bool
  default     = false
}

variable "saas_workspaces" {
  description = "SaaS workspace names to declare (saas-<name>, working dir envs/saas). Default [] = none."
  type        = list(string)
  default     = []
}

variable "terraform_version" {
  description = "Terraform version constraint applied to every managed workspace, e.g. ~> 1.9. Null uses the TFC default."
  type        = string
  default     = "~> 1.9"
}

variable "vcs_repo" {
  description = "Optional VCS connection applied to every workspace: {identifier = \"org/repo\", branch = \"main\", oauth_token_id = \"ot-...\"}. Null = API/CLI-driven workspaces."
  type = object({
    identifier     = string
    branch         = optional(string, "main")
    oauth_token_id = string
  })
  default = null
}

variable "common_workspace_variables" {
  description = "Variables set on EVERY managed workspace (in addition to tfc_organization), e.g. TFC_AWS_PROVIDER_AUTH. Keyed by name: {value, category (terraform|env), hcl?, sensitive?, description?}. Supply real secrets out-of-band, not here."
  type = map(object({
    value       = string
    category    = string
    hcl         = optional(bool, false)
    sensitive   = optional(bool, false)
    description = optional(string)
  }))
  default = {}
}
