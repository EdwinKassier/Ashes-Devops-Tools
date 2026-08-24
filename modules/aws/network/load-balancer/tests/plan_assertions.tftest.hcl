# Resource-wiring assertions for the load-balancer module.
# Asserts on config-derived, plan-knowable attributes only — set-typed and
# provider-normalized attributes resolve to UNKNOWN under mock_provider.

mock_provider "aws" {}

variables {
  name                  = "app-alb"
  vpc_id                = "vpc-0123456789abcdef0"
  subnet_ids            = ["subnet-aaa", "subnet-bbb"]
  load_balancer_type    = "application"
  internal              = true
  create_security_group = true

  target_groups = {
    web = {
      name        = "app-web-tg"
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
      certificate_arn  = "arn:aws:acm:eu-west-2:111122223333:certificate/abc"
    }
  }
}

run "load_balancer_wired_from_config" {
  command = plan

  assert {
    condition     = aws_lb.this.load_balancer_type == "application"
    error_message = "load balancer type must propagate from var.load_balancer_type"
  }

  assert {
    condition     = aws_lb.this.internal == true
    error_message = "internal flag must propagate from var.internal"
  }

  assert {
    condition     = aws_lb.this.name == "app-alb"
    error_message = "load balancer name must propagate from var.name"
  }

  # ALB header hardening default is on.
  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true
    error_message = "ALB must drop invalid header fields by default"
  }

  # Secure default: deletion protection on.
  assert {
    condition     = aws_lb.this.enable_deletion_protection == true
    error_message = "deletion protection must default to true"
  }
}

run "target_group_planned" {
  command = plan

  assert {
    condition     = length(aws_lb_target_group.this) == 1
    error_message = "exactly one target group must be planned"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].port == 8080
    error_message = "target group port must propagate from config"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].protocol == "HTTP"
    error_message = "target group protocol must propagate from config"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].target_type == "ip"
    error_message = "target group target_type must propagate from config"
  }
}

run "listener_planned" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.this) == 1
    error_message = "exactly one listener must be planned"
  }

  assert {
    condition     = aws_lb_listener.this["https"].port == 443
    error_message = "listener port must propagate from config"
  }

  assert {
    condition     = aws_lb_listener.this["https"].protocol == "HTTPS"
    error_message = "listener protocol must propagate from config"
  }

  assert {
    condition     = aws_lb_listener.this["https"].certificate_arn == "arn:aws:acm:eu-west-2:111122223333:certificate/abc"
    error_message = "listener certificate_arn must propagate from config"
  }

  assert {
    condition     = aws_lb_listener.this["https"].default_action[0].type == "forward"
    error_message = "listener default action must forward"
  }
}

run "security_group_created_when_opted_in" {
  command = plan

  assert {
    condition     = length(aws_security_group.this) == 1
    error_message = "a security group must be created when create_security_group = true"
  }

  assert {
    condition     = aws_security_group.this[0].vpc_id == "vpc-0123456789abcdef0"
    error_message = "the managed security group must live in the supplied vpc_id"
  }
}

run "network_lb_internet_facing" {
  command = plan

  variables {
    load_balancer_type    = "network"
    internal              = false
    create_security_group = false
    listeners = {
      tcp = {
        port             = 80
        protocol         = "TCP"
        target_group_key = "web"
      }
    }
    target_groups = {
      web = {
        name     = "app-web-tg"
        port     = 80
        protocol = "TCP"
      }
    }
  }

  assert {
    condition     = aws_lb.this.load_balancer_type == "network"
    error_message = "network load balancer type must propagate"
  }

  assert {
    condition     = aws_lb.this.internal == false
    error_message = "internet-facing flag must propagate"
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "no security group must be created when create_security_group = false"
  }
}
