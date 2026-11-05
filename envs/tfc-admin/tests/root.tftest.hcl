# Contract test for the tfc-admin root: the declared workspace set matches the
# cloud roots, driven by the environments map and the enable_aws / saas toggles.

mock_provider "tfe" {}

variables {
  tfc_organization = "acme"
  environments = {
    dev  = {}
    prod = {}
  }
  enable_aws      = true
  saas_workspaces = ["web"]
}

run "declares_every_workspace" {
  command = plan

  # 4 GCP control plane + 2 gcp-workload + 6 AWS control plane + 2 aws-workload +
  # 1 saas = 15.
  assert {
    condition     = length(output.workspace_names) == 15
    error_message = "tfc-admin must declare a workspace for each root, each per-env workload, and each saas entry."
  }

  assert {
    condition = alltrue([
      for k in ["gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub",
      "gcp-workload-dev", "gcp-workload-prod", "aws-security", "aws-workload-prod", "saas-web"] :
      contains(output.workspace_names, k)
    ])
    error_message = "control-plane, per-env workload, and saas workspaces must all be declared."
  }
}

run "gcp_only_by_default" {
  command = plan

  variables {
    enable_aws      = false
    saas_workspaces = []
  }

  # 4 GCP control plane + 2 gcp-workload = 6; no AWS workspaces.
  assert {
    condition     = length(output.workspace_names) == 6 && !contains(output.workspace_names, "aws-organization")
    error_message = "with enable_aws=false and no saas, only the GCP workspaces are declared."
  }
}
