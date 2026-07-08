# Example: provision a host project's core networking via the host
# compatibility wrapper (as consumed by envs/apps).
#
# This example creates a VPC, subnets, and supporting networking primitives
# inside an existing GCP project. Replace all locals with real values or
# remote state before use.

locals {
  project_id     = "my-host-project"
  project_prefix = "my-org-dev"
  region         = "us-central1"
}

module "example" {
  source = "../../"

  project_id     = local.project_id
  project_prefix = local.project_prefix
  region         = local.region

  vpc_cidr_block = "10.20.0.0/16"
  vpc_name       = "example-vpc"
}
