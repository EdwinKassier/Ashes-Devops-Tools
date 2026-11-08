# Basic working example for the aws/load-balancer module.
# Creates an INTERNAL application load balancer across two private subnets, with
# a module-managed security group whose egress is limited to the VPC CIDR, an
# HTTPS listener (TLS 1.3 policy) forwarding to an IP target group, an HTTP
# listener that redirects to HTTPS, and S3 access logging. Deletion protection
# stays at its secure default. Run `terraform init && terraform validate` here
# to check it.
#
# The VPC, subnet, certificate and bucket values are placeholders: replace them
# with your own.

module "load_balancer" {
  source = "../../"

  name       = "dev-app-alb"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]

  load_balancer_type    = "application"
  internal              = true
  create_security_group = true
  egress_cidr_blocks    = ["10.0.0.0/16"]

  target_groups = {
    web = {
      name        = "dev-app-web"
      port        = 8080
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
      certificate_arn  = "arn:aws:acm:eu-west-2:111122223333:certificate/11111111-2222-3333-4444-555555555555"
    }
    http = {
      port           = 80
      protocol       = "HTTP"
      default_action = "redirect-https"
    }
  }

  access_logs = {
    bucket = "example-lb-access-logs"
    prefix = "dev-app-alb"
  }

  tags = {
    environment = "dev"
  }
}
