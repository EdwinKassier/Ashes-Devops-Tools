# Input-validation suite for the aws-app-services stage.

mock_provider "aws" {}

variables {
  environment         = "dev"
  aws_region          = "eu-west-2"
  vpc_id              = "vpc-0123456789abcdef0"
  service_subnet_ids  = ["subnet-priv-a", "subnet-priv-b"]
  database_subnet_ids = ["subnet-iso-a", "subnet-iso-b"]
  kms_key_arn         = "arn:aws:kms:eu-west-2:111111111111:key/abcd-1234"
}

run "wildcard_subject_rejected" {
  command         = plan
  expect_failures = [var.services]
  variables {
    enable_github_oidc = true
    services           = { orders = { github = { repository = "acme/orders", subject = "repo:acme/orders:*" } } }
  }
}

run "wildcard_ref_rejected" {
  command         = plan
  expect_failures = [var.services]
  variables {
    enable_github_oidc = true
    services           = { orders = { github = { repository = "acme/orders", ref = "refs/heads/*" } } }
  }
}

run "bad_repository_rejected" {
  command         = plan
  expect_failures = [var.services]
  variables {
    services = { orders = { github = { repository = "orders" } } }
  }
}

run "bad_service_key_rejected" {
  command         = plan
  expect_failures = [var.services]
  variables {
    services = { Orders_API = {} }
  }
}

run "plaintext_secret_rejected" {
  command         = plan
  expect_failures = [var.services]
  variables {
    services = { orders = { secrets = { DB_PASSWORD = "hunter2" } } }
  }
}

run "services_without_kms_rejected" {
  command         = plan
  expect_failures = [var.kms_key_arn]
  variables {
    kms_key_arn = ""
    services    = { orders = {} }
  }
}

run "database_without_subnets_rejected" {
  command         = plan
  expect_failures = [var.database_subnet_ids]
  variables {
    database_subnet_ids = []
    services            = { orders = { database = {} } }
  }
}

run "existing_provider_without_arn_rejected" {
  command         = plan
  expect_failures = [var.create_github_oidc_provider]
  variables {
    enable_github_oidc          = true
    create_github_oidc_provider = false
  }
}

run "public_alb_without_certificate_rejected" {
  command         = plan
  expect_failures = [var.alb_certificate_arn]
  variables {
    alb_internal = false
  }
}
