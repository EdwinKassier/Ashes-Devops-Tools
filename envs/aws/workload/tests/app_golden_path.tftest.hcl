# Zero-hand-made-input golden path: the workload CMK is created in code, the
# first task revision runs a public placeholder image, and app_ingress_mode
# selects internal / public_alb / cloudfront_vpc_origin exposure.
#
# Contracts come from variables (no remote state); the CMK's ARN is pinned at
# plan with override_resource so its consumers can be asserted concretely.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  workload_account_key     = "workload_dev"
  config_role_arn          = "arn:aws:iam::222222222222:role/config-recorder"
  organization_contract    = { account_ids = { workload_dev = "222222222222" } }
  network_contract         = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } }
  security_contract        = { log_archive_bucket_name = "acme-org-log-archive" }
  services                 = { orders = {} }
}

run "workload_cmk_created_and_used_by_default" {
  command = plan

  override_resource {
    target          = aws_kms_key.workload
    override_during = plan
    values = {
      arn    = "arn:aws:kms:eu-west-2:222222222222:key/00000000-0000-0000-0000-00000000c0de"
      key_id = "00000000-0000-0000-0000-00000000c0de"
    }
  }

  assert {
    condition     = module.aws_workload.vpc_bpa_exclusion_enabled == false
    error_message = "internal ingress (default) must not create a VPC BPA exclusion"
  }

  assert {
    condition     = length(aws_kms_key.workload) == 1 && aws_kms_key.workload[0].enable_key_rotation && aws_kms_alias.workload[0].name == "alias/workload-dev"
    error_message = "kms_key_arn = \"\" must create a rotating workload CMK aliased alias/workload-<env>."
  }

  # CloudWatch Logs may use the key only for log groups in THIS account/region.
  assert {
    condition = one([
      for st in jsondecode(aws_kms_key.workload[0].policy).Statement : st.Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"]
      if try(st.Principal.Service, "") == "logs.eu-west-2.amazonaws.com"
    ]) == "arn:${data.aws_partition.current.partition}:logs:eu-west-2:222222222222:log-group:*"
    error_message = "The key policy must admit logs.<region>.amazonaws.com scoped by the aws:logs:arn encryption context."
  }

  assert {
    condition = (
      length([for st in jsondecode(aws_kms_key.workload[0].policy).Statement : st if try(st.Condition.StringEquals["kms:ViaService"], "") == "ecr.eu-west-2.amazonaws.com"]) == 1 &&
      length([for st in jsondecode(aws_kms_key.workload[0].policy).Statement : st if try(st.Condition.ArnLike["aws:PrincipalArn"], "") == "arn:${data.aws_partition.current.partition}:iam::222222222222:role/dev-*-exec"]) == 1
    )
    error_message = "The key policy must admit ECR (via service) and the dev-*-exec task execution roles."
  }

  assert {
    condition     = output.workload_kms_key_arn == "arn:aws:kms:eu-west-2:222222222222:key/00000000-0000-0000-0000-00000000c0de"
    error_message = "The created CMK must be the workload's key."
  }

  # ECR repos + log groups (+ Aurora / RDS secret) are encrypted with it.
  assert {
    condition     = module.app_services.kms_key_arn == output.workload_kms_key_arn
    error_message = "app-services (ECR repositories, log groups) must use the created CMK."
  }

  # First deploy: no :bootstrap tag to push by hand.
  assert {
    condition     = output.app_services["orders"].initial_image == "public.ecr.aws/nginx/nginx-unprivileged:stable-alpine"
    error_message = "The first task revision must run the public placeholder image by default."
  }

  # Default ingress: internal ALB, no public tier, no IGW, no edge.
  assert {
    condition = (
      output.app_ingress_mode == "internal" &&
      module.app_services.alb_internal == true &&
      !contains(keys(module.aws_workload.subnet_ids_by_tier), "public") &&
      length(module.app_edge) == 0
    )
    error_message = "The default app ingress must stay internal with no public subnets or edge."
  }
}

run "supplied_kms_key_is_used_and_none_created" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
  }

  assert {
    condition     = length(aws_kms_key.workload) == 0 && output.workload_kms_key_arn == var.kms_key_arn && module.app_services.kms_key_arn == var.kms_key_arn
    error_message = "A supplied kms_key_arn must be used everywhere and no CMK created."
  }
}

run "public_alb_mode" {
  command = plan

  variables {
    app_ingress_mode        = "public_alb"
    app_alb_certificate_arn = "arn:aws:acm:eu-west-2:222222222222:certificate/abcd"
  }

  # The org VPC BPA policy drops all IGW ingress unless THIS VPC is excluded.
  assert {
    condition     = module.aws_workload.vpc_bpa_exclusion_enabled == true
    error_message = "public_alb must create a VPC BPA exclusion for the spoke VPC, or the internet-facing ALB receives no traffic"
  }

  assert {
    condition     = module.app_services.alb_internal == false
    error_message = "public_alb must create an internet-facing ALB."
  }

  assert {
    condition     = contains(keys(module.aws_workload.subnet_ids_by_tier), "public") && length(module.aws_workload.subnet_ids_by_tier["public"]) == 2
    error_message = "public_alb must give the spoke a public subnet tier (one per AZ)."
  }

  assert {
    condition     = length(module.app_edge) == 1 && output.app_edge_distribution_id == null
    error_message = "public_alb must attach a regional WAF (edge-security) and no CloudFront distribution."
  }

  assert {
    condition     = length(local.app_alb_ingress_cidrs) == 1 && local.app_alb_ingress_cidrs[0] == "0.0.0.0/0"
    error_message = "An internet-facing ALB defaults its listener ingress to 0.0.0.0/0."
  }
}

run "public_alb_without_waf" {
  command = plan

  variables {
    app_ingress_mode        = "public_alb"
    app_alb_certificate_arn = "arn:aws:acm:eu-west-2:222222222222:certificate/abcd"
    enable_app_waf          = false
  }

  assert {
    condition     = length(module.app_edge) == 0
    error_message = "enable_app_waf = false must skip the regional WAF."
  }
}

run "cloudfront_vpc_origin_mode" {
  command = plan

  variables {
    app_ingress_mode = "cloudfront_vpc_origin"
  }

  assert {
    condition     = module.app_services.alb_internal == true && !contains(keys(module.aws_workload.subnet_ids_by_tier), "public")
    error_message = "cloudfront_vpc_origin keeps the ALB internal with no public subnets."
  }

  assert {
    condition     = length(module.app_edge) == 1
    error_message = "cloudfront_vpc_origin must create the CloudFront edge (VPC origin + WAF)."
  }
}

run "ingress_mode_and_bootstrap_image_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-app.yaml"
  }

  assert {
    condition     = output.app_ingress_mode == "cloudfront_vpc_origin" && length(module.app_edge) == 1
    error_message = "aws.workload.app_ingress_mode in config/landing-zone.yaml must select the ingress mode."
  }

  assert {
    condition     = output.app_services["orders"].initial_image == "123456789012.dkr.ecr.eu-west-2.amazonaws.com/mirror/nginx-unprivileged:stable-alpine"
    error_message = "aws.workload.bootstrap_image must override the placeholder image."
  }
}

run "public_alb_requires_certificate" {
  command = plan

  variables {
    app_ingress_mode = "public_alb"
  }

  expect_failures = [var.app_ingress_mode]
}

run "cloudfront_vpc_origin_rejects_alb_certificate" {
  command = plan

  variables {
    app_ingress_mode        = "cloudfront_vpc_origin"
    app_alb_certificate_arn = "arn:aws:acm:eu-west-2:222222222222:certificate/abcd"
  }

  expect_failures = [var.app_ingress_mode]
}

run "rejects_unknown_ingress_mode" {
  command = plan

  variables {
    app_ingress_mode = "nlb"
  }

  expect_failures = [var.app_ingress_mode]
}

run "public_mode_without_services_builds_no_public_tier" {
  command = plan

  variables {
    services                = {}
    app_ingress_mode        = "public_alb"
    app_alb_certificate_arn = "arn:aws:acm:eu-west-2:222222222222:certificate/abcd"
  }

  assert {
    condition     = !contains(keys(module.aws_workload.subnet_ids_by_tier), "public") && length(module.app_edge) == 0 && output.app_endpoint == null
    error_message = "No public tier, IGW or WAF until a service exists."
  }
}
