# Private Service Connect Module

This module creates a Private Service Connect (PSC) endpoint to access Google APIs securely from within your VPC, without using public IP addresses.

## Features

- **Secure Access**: Access APIs like Storage, BigQuery, and more over private IP.
- **DNS Integration**: automatically creates a private DNS zone for `googleapis.com` pointing to the endpoint.
- **Global Access**: Reserves a global internal IP address.

## Usage

```hcl
module "psc_apis" {
  source = "./modules/network/private-service-connect"

  project_id = "my-project-id"
  name       = "psc-googleapis"
  network    = "projects/my-project/global/networks/my-vpc"
  target     = "all-apis"  # or "vpc-sc"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `name` | Name of the PSC endpoint | `string` | n/a | yes |
| `network` | VPC network self-link | `string` | n/a | yes |
| `target` | Target bundle (`all-apis`, `vpc-sc`) | `string` | `"all-apis"` | no |
| `address` | Specific IP to reserve | `string` | `null` | no |
| `create_dns_zone` | Create split-horizon DNS zone | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `address` | The reserved global internal IP |
| `forwarding_rule` | The PSC forwarding rule |
| `dns_zone` | The private DNS zone resource |
