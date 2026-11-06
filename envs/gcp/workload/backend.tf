terraform {
  # HCP Terraform (Terraform Cloud). The `cloud` block takes no -backend-config,
  # so supply the organization through the environment:
  #   export TF_CLOUD_ORGANIZATION=<your-tfc-org>
  #   export TF_CLOUD_HOSTNAME=app.terraform.io   # optional; set for HCP EU / TFE
  # One workspace per environment, selected by name: TF_WORKSPACE=gcp-workload-<env>
  # (envs/tfc-admin tags every gcp-workload-<env> workspace with these tags).
  cloud {
    workspaces {
      tags = ["cloud:gcp", "layer:workload"]
    }
  }
}
