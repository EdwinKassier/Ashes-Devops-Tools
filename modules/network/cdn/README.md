# Cloud CDN Module (Global Load Balancer)

This module provisions a Global External HTTPS Load Balancer served via Cloud CDN. It is the primary entrypoint for public internet traffic.

## Features

- **Global Reach**: Uses Google's global edge network.
- **SSL Termination**: Manages Google-managed SSL certificates automatically.
- **Dynamic Backends**: Supports multiple backend types (Serverless NEGs, Instance Groups) via a flexible configuration list.
- **Security**: Integrated Cloud Armor security policies.
- **CDN**: Caching enabled by default (configurable per backend).

## Usage

```hcl
module "cdn" {
  source = "./modules/network/cdn"

  project_id = "my-project-id"
  lb_name    = "main-lb"
  domains    = ["example.com", "www.example.com"]

  backend_groups = [
    {
      group = module.api_gateway.serverless_neg_id
      description = "API Gateway Backend"
    }
  ]

  security_policy = module.cloud_armor.policy_self_link
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Project ID | `string` | n/a | yes |
| `lb_name` | Name of the Load Balancer | `string` | n/a | yes |
| `domains` | List of domains for SSL certs | `list(string)` | n/a | yes |
| `backend_groups` | List of backend objects | `list(object)` | `[]` | yes |
| `security_policy` | Cloud Armor policy self-link | `string` | `null` | no |
| `enable_cdn` | Enable CDN features | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `load_balancer_ip` | The reserved global static IP |
| `backend_service_id` | The backend service ID |
