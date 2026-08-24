# load-balancer

Elastic Load Balancing (ALB / NLB) primitive for the AWS landing zone — the
parity counterpart to GCP's `modules/gcp/network/internal-lb`. Creates an
`aws_lb` (application or network, internal or internet-facing), a set of
`aws_lb_target_group`s, and their `aws_lb_listener`s, with secure defaults
(deletion protection on, ALB invalid-header dropping on) and optional S3 access
logging and a managed security group.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name = 
	subnet_ids = 
	vpc_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_lb.this (modules/aws/network/load-balancer/main.tf#L59)
- resource.aws_lb_listener.this (modules/aws/network/load-balancer/main.tf#L119)
- resource.aws_lb_target_group.this (modules/aws/network/load-balancer/main.tf#L88)
- resource.aws_security_group.this (modules/aws/network/load-balancer/main.tf#L33)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Name of the load balancer. Also used as the Name tag and the prefix for the managed security group. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs the load balancer is attached to. Provide at least two subnets in different AZs for production availability. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC the target groups (and the optional managed security group) live in. | `string` | n/a | yes |
| <a name="input_access_logs"></a> [access\_logs](#input\_access\_logs) | Optional S3 access logging. Provide bucket (and optional prefix); set enabled=false to configure the destination without turning logging on. | <pre>object({<br/>    bucket  = string<br/>    prefix  = optional(string, "")<br/>    enabled = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create\_security\_group) | Whether this module creates a security group for the load balancer (typically for an ALB). The caller adds ingress rules via the exported security\_group\_id. | `bool` | `false` | no |
| <a name="input_drop_invalid_header_fields"></a> [drop\_invalid\_header\_fields](#input\_drop\_invalid\_header\_fields) | For application load balancers, drop HTTP headers with invalid fields. Ignored for network load balancers. | `bool` | `true` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Protect the load balancer from accidental deletion. Defaults to true; set false only for ephemeral/test load balancers. | `bool` | `true` | no |
| <a name="input_internal"></a> [internal](#input\_internal) | Whether the load balancer is internal (true, no public IPs) or internet-facing (false). | `bool` | `true` | no |
| <a name="input_listeners"></a> [listeners](#input\_listeners) | Listeners to create, keyed by a stable local key. Each listener forwards to<br/>the target group named by target\_group\_key. Provide certificate\_arn (and<br/>optionally ssl\_policy) for TLS-terminating listeners (HTTPS/TLS). | <pre>map(object({<br/>    port             = number<br/>    protocol         = string<br/>    target_group_key = string<br/>    certificate_arn  = optional(string)<br/>    ssl_policy       = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")<br/>  }))</pre> | `{}` | no |
| <a name="input_load_balancer_type"></a> [load\_balancer\_type](#input\_load\_balancer\_type) | Load balancer type: 'application' (L7 ALB) or 'network' (L4 NLB). | `string` | `"application"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security group IDs to attach to the load balancer. Merged with the module-created group when create\_security\_group = true. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the load balancer, target groups, listeners, and managed security group. | `map(string)` | `{}` | no |
| <a name="input_target_groups"></a> [target\_groups](#input\_target\_groups) | Target groups to create, keyed by a stable local key referenced from listeners.<br/>Each entry configures protocol, port, target\_type, and an optional health\_check. | <pre>map(object({<br/>    name        = string<br/>    port        = number<br/>    protocol    = string<br/>    target_type = optional(string, "instance")<br/>    health_check = optional(object({<br/>      enabled             = optional(bool, true)<br/>      path                = optional(string, "/")<br/>      port                = optional(string, "traffic-port")<br/>      protocol            = optional(string, "HTTP")<br/>      healthy_threshold   = optional(number, 3)<br/>      unhealthy_threshold = optional(number, 3)<br/>      interval            = optional(number, 30)<br/>      timeout             = optional(number, 5)<br/>      matcher             = optional(string, "200")<br/>    }))<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | ARN of the load balancer. |
| <a name="output_arn_suffix"></a> [arn\_suffix](#output\_arn\_suffix) | ARN suffix of the load balancer, for use in CloudWatch metric dimensions. |
| <a name="output_dns_name"></a> [dns\_name](#output\_dns\_name) | DNS name of the load balancer. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the module-created security group, or null when create\_security\_group = false. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Map of target group key to the created target group ARN. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | Route 53 hosted zone ID of the load balancer, for alias records. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "app_lb" {
  source = "../../modules/aws/network/load-balancer"

  name       = "app-alb"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]

  load_balancer_type    = "application"
  internal              = false
  create_security_group = true

  target_groups = {
    web = {
      name        = "app-web-tg"
      port        = 80
      protocol    = "HTTP"
      target_type = "ip"
      health_check = {
        path = "/healthz"
      }
    }
  }

  listeners = {
    https = {
      port             = 443
      protocol         = "HTTPS"
      target_group_key = "web"
      certificate_arn  = "arn:aws:acm:eu-west-2:111122223333:certificate/abc"
    }
  }

  access_logs = {
    bucket = "my-lb-access-logs"
    prefix = "app-alb"
  }

  tags = {
    Environment = "prod"
  }
}
```
