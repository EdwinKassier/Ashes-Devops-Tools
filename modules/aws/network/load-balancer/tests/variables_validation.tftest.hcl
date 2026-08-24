# Variable validation tests for the load-balancer module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation, so these pass regardless of
# mock provider behaviour.

mock_provider "aws" {}

# Minimum required variables shared across all runs.
variables {
  name       = "app-alb"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]
}

# ── var.name ─────────────────────────────────────────────────────────────────

run "valid_name_accepted" {
  command = plan

  variables {
    name = "app-alb"
  }
}

run "invalid_name_rejected" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "-bad-leading-hyphen"
  }
}

# ── var.vpc_id ───────────────────────────────────────────────────────────────

run "invalid_vpc_id_rejected" {
  command = plan

  expect_failures = [var.vpc_id]

  variables {
    vpc_id = "not-a-vpc"
  }
}

# ── var.subnet_ids ───────────────────────────────────────────────────────────

run "empty_subnet_ids_rejected" {
  command = plan

  expect_failures = [var.subnet_ids]

  variables {
    subnet_ids = []
  }
}

# ── var.load_balancer_type ───────────────────────────────────────────────────

run "invalid_load_balancer_type_rejected" {
  command = plan

  expect_failures = [var.load_balancer_type]

  variables {
    load_balancer_type = "gateway"
  }
}

# ── var.target_groups ────────────────────────────────────────────────────────

run "invalid_target_group_protocol_rejected" {
  command = plan

  expect_failures = [var.target_groups]

  variables {
    target_groups = {
      web = {
        name     = "app-web-tg"
        port     = 80
        protocol = "GOPHER"
      }
    }
  }
}

run "invalid_target_group_target_type_rejected" {
  command = plan

  expect_failures = [var.target_groups]

  variables {
    target_groups = {
      web = {
        name        = "app-web-tg"
        port        = 80
        protocol    = "HTTP"
        target_type = "container"
      }
    }
  }
}

# ── var.listeners ────────────────────────────────────────────────────────────

run "https_listener_without_certificate_rejected" {
  command = plan

  expect_failures = [var.listeners]

  variables {
    target_groups = {
      web = {
        name     = "app-web-tg"
        port     = 80
        protocol = "HTTP"
      }
    }
    listeners = {
      https = {
        port             = 443
        protocol         = "HTTPS"
        target_group_key = "web"
        # certificate_arn intentionally omitted
      }
    }
  }
}

run "valid_listeners_and_target_groups_accepted" {
  command = plan

  variables {
    target_groups = {
      web = {
        name     = "app-web-tg"
        port     = 80
        protocol = "HTTP"
      }
    }
    listeners = {
      http = {
        port             = 80
        protocol         = "HTTP"
        target_group_key = "web"
      }
    }
  }
}
