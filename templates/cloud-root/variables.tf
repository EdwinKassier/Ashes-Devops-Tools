# Required variables — no defaults, callers must supply these.

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns the remote-state workspaces this root reads. Used in every terraform_remote_state config block so state resolves at plan time without cloud credentials."
  type        = string
}

# Optional variables — add your cloud's region / enabled-region inputs here,
# following templates/aws-root/variables.tf (region-shaped validation with
# interval repeats kept <= 1000 for the RE2 engine).
