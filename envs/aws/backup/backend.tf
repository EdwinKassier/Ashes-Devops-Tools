terraform {
  # HCP Terraform (Terraform Cloud). The `cloud` block takes no -backend-config,
  # so supply the organization through the environment:
  #   export TF_CLOUD_ORGANIZATION=<your-tfc-org>
  #   export TF_CLOUD_HOSTNAME=app.terraform.io   # optional; set for HCP EU / TFE
  cloud {
    workspaces {
      name = "aws-backup"
    }
  }
}
