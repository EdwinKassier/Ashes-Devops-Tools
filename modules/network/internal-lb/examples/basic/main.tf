# Example: create an L7 internal load balancer in front of a managed instance group.

locals {
  project_id = "my-workload-project"
  region     = "us-central1"
  network    = "projects/my-workload-project/global/networks/my-vpc"
  subnet     = "projects/my-workload-project/regions/us-central1/subnetworks/private-us-central1"
  backend_ig = "projects/my-workload-project/zones/us-central1-a/instanceGroups/backend-mig"
}

module "internal_lb" {
  source = "../../"

  project_id = local.project_id
  name       = "backend-ilb"
  region     = local.region
  network    = local.network
  subnet     = local.subnet

  backends = [
    { group = local.backend_ig }
  ]

  is_l7                    = true
  health_check_type        = "HTTP"
  health_check_request_path = "/healthz"
}

output "load_balancer_ip" {
  description = "Internal VIP of the load balancer"
  value       = module.internal_lb.ip_address
}
