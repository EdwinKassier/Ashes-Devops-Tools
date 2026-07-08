# Example: create a custom-mode VPC with default routes removed.
# Replace locals with data sources or remote state.

locals {
  project_id = "my-project"
}

module "example" {
  source = "../../"

  project_id = local.project_id
  vpc_name   = "example-vpc"

  # auto_create_subnetworks = false (default) — subnets are managed explicitly,
  # e.g. via modules/network/subnet.
  # delete_default_routes_on_create = true (default) — removes the implicit
  # 0.0.0.0/0 default route so routing is fully explicit.
}
