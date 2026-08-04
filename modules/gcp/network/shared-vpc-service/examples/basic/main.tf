# Example: attach a service project to a Shared VPC host project and grant
# the Cloud Services SA the networkUser role on specific subnets.

locals {
  host_project_id    = "my-hub-project"
  service_project_id = "my-workload-project"
}

module "shared_vpc_attachment" {
  source = "../../"

  host_project_id    = local.host_project_id
  service_project_id = local.service_project_id

  # Grant networkUser on specific subnets (rather than all subnets in the VPC).
  # Replace PROJECT_NUMBER with the numeric project number of the service project.
  subnet_iam_bindings = [
    {
      subnet = "private-us-central1"
      region = "us-central1"
      member = "serviceAccount:PROJECT_NUMBER@cloudservices.gserviceaccount.com"
    }
  ]
}
