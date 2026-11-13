# Example: create an L7 internal load balancer in front of a managed instance group.
# An L7 (INTERNAL_MANAGED) load balancer needs at least one host rule and a
# proxy-only subnet in the region; the module opens the backend port from that
# subnet to the tagged backends.

locals {
  project_id = "my-workload-project"
  region     = "us-central1"
  network    = "projects/my-workload-project/global/networks/my-vpc"
  subnet     = "projects/my-workload-project/regions/us-central1/subnetworks/private-us-central1"
  backend_ig = "projects/my-workload-project/zones/us-central1-a/instanceGroups/backend-mig"

  # The region's REGIONAL_MANAGED_PROXY subnet.
  proxy_only_range = "10.129.0.0/23"
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

  is_l7                     = true
  health_check_type         = "HTTP"
  health_check_request_path = "/healthz"

  # Route every host to this load balancer's own backend service.
  host_rules = [
    { hosts = ["*"], path_matcher = "default" }
  ]
  path_matchers = [
    { name = "default", default_service = module.internal_lb.backend_service_self_link }
  ]

  proxy_only_subnet_ranges = [local.proxy_only_range]
  backend_target_tags      = ["backend"]
}
