# gke-autopilot

Creates a private, Autopilot-mode GKE cluster attached to a Shared VPC. Secure by
default: private nodes, a private control-plane endpoint, Workload Identity always
on, deletion protection, and the Gateway API controller enabled.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs output goes here — run `make docs` to regenerate -->
<!-- END_TF_DOCS -->

## Usage

```hcl
module "gke" {
  source = "../../modules/gcp/compute/gke-autopilot"

  project_id = "my-project-id"
  name       = "app-platform"
  location   = "europe-west1"

  network    = module.vpc.self_link
  subnetwork = module.subnet.self_link

  cluster_secondary_range_name  = "pods"
  services_secondary_range_name = "services"

  # Private endpoint is the default; expose it only to known networks if required.
  # enable_private_endpoint = false
  # master_authorized_networks = [
  #   { cidr_block = "10.0.0.0/8", display_name = "corp" },
  # ]
}
```
