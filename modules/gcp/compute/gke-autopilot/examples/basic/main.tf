# Example: a regional GKE Autopilot cluster on a Shared VPC subnet with a
# private control-plane endpoint (no public IP), private nodes, named
# secondary ranges for pods and services, the STABLE release channel and
# deletion protection on.
#
# The host network, subnet and its secondary ranges must already exist (e.g.
# from gcp/network/tiered-vpc). Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

module "gke" {
  source = "../../"

  project_id = "my-project-id"
  name       = "apps-autopilot"
  location   = "europe-west2"

  network    = "projects/my-host-project/global/networks/shared-vpc"
  subnetwork = "projects/my-host-project/regions/europe-west2/subnetworks/gke-subnet"

  cluster_secondary_range_name  = "gke-pods"
  services_secondary_range_name = "gke-services"

  release_channel = "STABLE"

  # Default, shown for clarity: the control plane is reachable only from the VPC.
  enable_private_endpoint = true
  master_ipv4_cidr_block  = "172.16.0.32/28"
  master_authorized_networks = [
    { cidr_block = "10.10.0.0/24", display_name = "ops-bastion-subnet" },
  ]

  enable_deletion_protection = true

  labels = {
    env = "dev"
  }
}
