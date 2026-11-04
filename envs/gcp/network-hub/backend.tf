terraform {
  backend "cloud" {
    # Supply organization via TF_CLI_ARGS_init or a gitignored backend.hcl.
    workspaces {
      name = "gcp-network-hub"
    }
  }
}
