# gke-autopilot

Creates a private, Autopilot-mode GKE cluster attached to a Shared VPC. Secure by
default: private nodes, a private control-plane endpoint, Workload Identity always
on, deletion protection, and the Gateway API controller enabled.

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

GKE Autopilot Module - Main Configuration

Creates a private, Autopilot-mode Google Kubernetes Engine cluster attached to
a Shared VPC. Secure by default: private nodes, a private control-plane endpoint,
Workload Identity always on, deletion protection, and a Gateway API controller.
Every hardening control is a toggle so platform admins can compose the posture
they need without forking the module.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	location = 
	name = 
	network = 
	project_id = 
	subnetwork = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |



## Resources

The following resources are created:


- resource.google_container_cluster.this (modules/gcp/compute/gke-autopilot/main.tf#L33)
- resource.terraform_data.deletion_protection_guard (modules/gcp/compute/gke-autopilot/main.tf#L23)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_location"></a> [location](#input\_location) | The GCP region to host the regional Autopilot cluster in (e.g. europe-west1). Autopilot clusters are always regional. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the GKE Autopilot cluster | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The self\_link or name of the Shared VPC network to attach the cluster to | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where the cluster will be created | `string` | n/a | yes |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | The self\_link or name of the Shared VPC subnetwork to attach the cluster nodes to | `string` | n/a | yes |
| <a name="input_cluster_secondary_range_name"></a> [cluster\_secondary\_range\_name](#input\_cluster\_secondary\_range\_name) | Name of the subnetwork secondary range to use for pod IPs. Leave null to let GKE allocate a range automatically. | `string` | `null` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Prevent accidental destruction of the cluster.<br/><br/>When true, the cluster's own deletion\_protection API attribute is set and a<br/>terraform\_data guard resource is created with prevent\_destroy = true, so<br/>Terraform refuses to destroy this module. To intentionally remove a protected<br/>cluster, set this to false (which also removes the guard) and apply, or run:<br/>  terraform state rm 'module.<name>.terraform\_data.deletion\_protection\_guard' | `bool` | `true` | no |
| <a name="input_enable_private_endpoint"></a> [enable\_private\_endpoint](#input\_enable\_private\_endpoint) | When true, the cluster's control-plane endpoint has no public IP and is reachable only from within the VPC. Nodes are always private. | `bool` | `true` | no |
| <a name="input_master_authorized_networks"></a> [master\_authorized\_networks](#input\_master\_authorized\_networks) | List of CIDR blocks allowed to reach the control-plane endpoint. Required (non-empty) when enable\_private\_endpoint = false so a public endpoint is never left open to the internet. | <pre>list(object({<br/>    cidr_block   = string<br/>    display_name = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_master_ipv4_cidr_block"></a> [master\_ipv4\_cidr\_block](#input\_master\_ipv4\_cidr\_block) | The /28 CIDR range for the hosted control-plane (master) network. Must not overlap any other range in the VPC. | `string` | `"172.16.0.0/28"` | no |
| <a name="input_release_channel"></a> [release\_channel](#input\_release\_channel) | The GKE release channel the cluster subscribes to for automatic version upgrades | `string` | `"REGULAR"` | no |
| <a name="input_resource_labels"></a> [resource\_labels](#input\_resource\_labels) | A map of key/value labels to apply to the cluster | `map(string)` | `{}` | no |
| <a name="input_services_secondary_range_name"></a> [services\_secondary\_range\_name](#input\_services\_secondary\_range\_name) | Name of the subnetwork secondary range to use for service (ClusterIP) IPs. Leave null to let GKE allocate a range automatically. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ca_certificate"></a> [ca\_certificate](#output\_ca\_certificate) | Base64-encoded public certificate of the cluster's certificate authority |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | The IP address of the cluster's Kubernetes control-plane endpoint |
| <a name="output_name"></a> [name](#output\_name) | The name of the GKE Autopilot cluster |
| <a name="output_workload_pool"></a> [workload\_pool](#output\_workload\_pool) | The Workload Identity pool (<project>.svc.id.goog) bound to the cluster |
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
