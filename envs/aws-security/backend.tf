terraform {
  backend "cloud" {
    # Supply organization via TF_CLI_ARGS_init or a gitignored backend.hcl:
    #   export TF_CLI_ARGS_init="-backend-config=organization=<your-tfc-org>"
    # or create backend.hcl with: organization = "<your-tfc-org>"
    # and run: terraform init -backend-config=backend.hcl

    workspaces {
      name = "aws-security"
    }
  }
}
