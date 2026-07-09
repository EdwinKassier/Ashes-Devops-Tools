# Required variables — no defaults, callers must supply these.

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns the remote-state workspaces this root reads. Used in every terraform_remote_state config block so state resolves at plan time without cloud credentials."
  type        = string
}

# Optional variables — document sensible defaults and constraints.

variable "aws_region" {
  description = "Primary AWS region for the default provider (e.g. eu-west-2)."
  type        = string
  default     = "eu-west-2"

  # AWS region names are short (well under the RE2 1000-repeat cap). Shape:
  # <geo>-<direction>-<number>, e.g. eu-west-2, us-east-1, ap-southeast-3.
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "aws_enabled_regions" {
  description = "Regions this root manages resources in. Defaults to the primary region only; extend for multi-region roots."
  type        = list(string)
  default     = ["eu-west-2"]
}
