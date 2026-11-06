# Plan assertions for the aws-app-services golden-path stage (mock_provider —
# no credentials). override_during = plan makes the mocked computed values
# (ARNs, ids) known at plan time so the jsonencoded IAM policies can be decoded
# and asserted exactly.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:eu-west-2:111111111111:cluster/dev-apps" }
  }
  mock_resource "aws_ecs_service" {
    defaults = { id = "arn:aws:ecs:eu-west-2:111111111111:service/dev-apps/orders" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:eu-west-2:111111111111:repository/orders"
      repository_url = "111111111111.dkr.ecr.eu-west-2.amazonaws.com/orders"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/dev-orders/0123456789abcdef"
      arn_suffix = "targetgroup/dev-orders/0123456789abcdef"
    }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef0" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-2:111111111111:log-group:/ecs/dev/orders" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      endpoint = "dev-orders.cluster-abc.eu-west-2.rds.amazonaws.com"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:eu-west-2:111111111111:secret:rds!cluster-abc-AbCdEf"
        kms_key_id    = "arn:aws:kms:eu-west-2:111111111111:key/abcd-1234"
        secret_status = "active"
      }]
    }
  }
}

variables {
  environment         = "dev"
  aws_region          = "eu-west-2"
  vpc_id              = "vpc-0123456789abcdef0"
  vpc_cidr            = "10.20.0.0/16"
  service_subnet_ids  = ["subnet-priv-a", "subnet-priv-b"]
  database_subnet_ids = ["subnet-iso-a", "subnet-iso-b"]
  kms_key_arn         = "arn:aws:kms:eu-west-2:111111111111:key/abcd-1234"
}

# ── Default: an empty services map creates NOTHING ───────────────────────────

run "default_creates_nothing" {
  command = plan

  variables {
    vpc_id              = null
    service_subnet_ids  = []
    database_subnet_ids = []
    kms_key_arn         = ""
  }

  assert {
    condition = (
      length(aws_ecs_cluster.this) == 0 &&
      length(module.ecr) == 0 &&
      length(module.alb) == 0 &&
      length(module.service) == 0 &&
      length(module.database) == 0 &&
      length(module.alarms) == 0 &&
      length(aws_iam_role.execution) == 0 &&
      length(aws_iam_role.deploy) == 0 &&
      length(aws_iam_openid_connect_provider.github) == 0 &&
      length(aws_cloudwatch_log_group.service) == 0 &&
      length(data.aws_caller_identity.current) == 0
    )
    error_message = "services = {} with enable_github_oidc = false must create nothing."
  }
}

# ── One service: ECR + deploy role + Fargate service behind an internal ALB ──

run "one_service_golden_path" {
  command = plan

  variables {
    enable_github_oidc = true
    services = {
      orders = {
        github = { repository = "acme/orders" }
      }
    }
  }

  assert {
    condition     = length(aws_ecs_cluster.this) == 1 && aws_ecs_cluster.this[0].name == "dev-apps"
    error_message = "a non-empty services map must create the shared dev-apps cluster."
  }

  assert {
    condition     = keys(module.ecr[0].repository_arns) == ["orders"]
    error_message = "each service must get its own ECR repository."
  }

  assert {
    condition     = length(module.service) == 1 && output.services["orders"].ecs_service_name == "orders"
    error_message = "each service must get a Fargate service."
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1 && aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com" && length(aws_iam_openid_connect_provider.github[0].client_id_list) == 1 && contains(aws_iam_openid_connect_provider.github[0].client_id_list, "sts.amazonaws.com")
    error_message = "enable_github_oidc must create the GitHub OIDC provider with audience sts.amazonaws.com."
  }

  # Trust: exact aud AND exact sub, federated to the GitHub provider, nothing else.
  assert {
    condition = (
      jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:acme/orders:environment:dev" &&
      jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
      keys(jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement[0].Condition) == ["StringEquals"] &&
      jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" &&
      length(jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement) == 1
    )
    error_message = "the deploy role must trust only aud=sts.amazonaws.com and the exact sub repo:acme/orders:environment:dev (StringEquals, no wildcards)."
  }

  # Permissions: push to ITS repo, roll ITS service, pass ONLY its task roles.
  assert {
    condition = (
      [for s in jsondecode(aws_iam_role_policy.deploy["orders"].policy).Statement : s.Resource if s.Sid == "EcrPushOwnRepo"][0] == "arn:aws:ecr:eu-west-2:111111111111:repository/orders" &&
      [for s in jsondecode(aws_iam_role_policy.deploy["orders"].policy).Statement : s.Resource if s.Sid == "EcsRollOwnService"][0] == "arn:aws:ecs:eu-west-2:111111111111:service/dev-apps/orders" &&
      [for s in jsondecode(aws_iam_role_policy.deploy["orders"].policy).Statement : s.Condition.StringEquals["iam:PassedToService"] if s.Sid == "PassOwnTaskRoles"][0] == "ecs-tasks.amazonaws.com" &&
      length([for s in jsondecode(aws_iam_role_policy.deploy["orders"].policy).Statement : s.Resource if s.Sid == "PassOwnTaskRoles"][0]) == 2
    )
    error_message = "the deploy role must be scoped to its own ECR repo, its own ECS service, and PassRole on its own two task roles to ecs-tasks only."
  }

  # The service is rolled by CI, so Terraform must not revert task definitions.
  assert {
    condition     = output.services["orders"].deploy_role_arn != null && output.services["orders"].task_definition_family == "dev-orders"
    error_message = "the service contract must expose the deploy role and task-definition family."
  }

  # Internal ALB by default, plain HTTP 80 only inside the network when no cert.
  assert {
    condition     = output.alb_internal == true && keys(module.alb[0].listener_arns) == ["http"]
    error_message = "the shared ALB must be internal by default."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.alb["80|10.20.0.0/16"].cidr_ipv4 == "10.20.0.0/16" && length(aws_vpc_security_group_ingress_rule.alb) == 1
    error_message = "the ALB must only admit the spoke VPC CIDR by default."
  }

  # Log group: KMS + retention.
  assert {
    condition     = aws_cloudwatch_log_group.service["orders"].kms_key_id == var.kms_key_arn && aws_cloudwatch_log_group.service["orders"].retention_in_days == 365
    error_message = "the service log group must be KMS-encrypted with bounded retention."
  }

  # Execution role: own repo + own log group, no secrets statement without secrets.
  assert {
    condition = (
      [for s in jsondecode(aws_iam_role_policy.execution["orders"].policy).Statement : s.Resource if s.Sid == "EcrPullOwnRepo"][0] == "arn:aws:ecr:eu-west-2:111111111111:repository/orders" &&
      [for s in jsondecode(aws_iam_role_policy.execution["orders"].policy).Statement : s.Resource if s.Sid == "WriteOwnLogGroup"][0] == "arn:aws:logs:eu-west-2:111111111111:log-group:/ecs/dev/orders:*" &&
      length([for s in jsondecode(aws_iam_role_policy.execution["orders"].policy).Statement : s if s.Sid == "ReadOwnSecrets"]) == 0
    )
    error_message = "the execution role must be scoped to the service's own repo and log group."
  }

  assert {
    condition     = jsondecode(aws_iam_role.execution["orders"].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111"
    error_message = "the ECS task roles must carry an aws:SourceAccount confused-deputy guard."
  }

  assert {
    condition     = length(module.database) == 0 && length(aws_security_group.database) == 0
    error_message = "no database unless the service sets database."
  }

  assert {
    condition     = length(module.alarms) == 1
    error_message = "alarms are on by default for a non-empty services map."
  }
}

# ── No github block => no deploy role; Terraform owns the task definition ───

run "service_without_github_has_no_deploy_role" {
  command = plan

  variables {
    enable_github_oidc = false
    services           = { orders = {} }
  }

  assert {
    condition     = length(aws_iam_role.deploy) == 0 && length(aws_iam_openid_connect_provider.github) == 0 && output.services["orders"].deploy_role_arn == null
    error_message = "a service without github (or with enable_github_oidc = false) must get no deploy role."
  }
}

# ── Subject variants: ref, custom (customised sub claim template) ───────────

run "github_subject_variants" {
  command = plan

  variables {
    enable_github_oidc = true
    services = {
      api = { github = { repository = "acme/api", ref = "refs/heads/main" } }
      web = { github = { repository = "acme/web", subject = "repository_owner_id:1234:repository_id:5678:environment:dev" } }
      ops = { github = { repository = "acme/ops", environment = "dev-approval" } }
    }
  }

  assert {
    condition = (
      output.github_oidc_subjects["api"] == "repo:acme/api:ref:refs/heads/main" &&
      output.github_oidc_subjects["web"] == "repository_owner_id:1234:repository_id:5678:environment:dev" &&
      output.github_oidc_subjects["ops"] == "repo:acme/ops:environment:dev-approval"
    )
    error_message = "subject precedence must be subject > ref > environment."
  }
}

# ── Immutable repository-ID subject (customised claim template) ─────────────

run "github_repository_id_subject_is_default_when_ids_set" {
  command = plan

  variables {
    enable_github_oidc = true
    services = {
      orders = { github = { repository = "acme/orders", repository_id = "5678", repository_owner_id = "1234" } }
      api    = { github = { repository = "acme/api", repository_id = "9012", repository_owner_id = "1234", ref = "refs/heads/main" } }
    }
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repository_owner_id:1234:repository_id:5678:environment:dev" &&
      output.github_oidc_subjects["api"] == "repository_owner_id:1234:repository_id:9012:ref:refs/heads/main"
    )
    error_message = "with repository_id set, the deploy-role sub must be the immutable ID-based subject (environment or ref context)."
  }

  assert {
    condition     = !strcontains(jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"], "repo:acme/orders")
    error_message = "the ID-based subject must not fall back to the mutable repository name."
  }
}

# ── Existing OIDC provider is reused, not recreated ─────────────────────────

run "existing_oidc_provider_reused" {
  command = plan

  variables {
    enable_github_oidc          = true
    create_github_oidc_provider = false
    github_oidc_provider_arn    = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
    services                    = { orders = { github = { repository = "acme/orders" } } }
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && jsondecode(aws_iam_role.deploy["orders"].assume_role_policy).Statement[0].Principal.Federated == var.github_oidc_provider_arn
    error_message = "create_github_oidc_provider = false must reuse github_oidc_provider_arn."
  }
}

# ── Database: private, not public, reachable only from the service SG ──────

run "database_private_and_service_only" {
  command = plan

  # Distinct id for the DB SG so the ingress-rule direction is actually proven.
  override_resource {
    target          = aws_security_group.database
    override_during = plan
    values          = { id = "sg-0database00000000" }
  }

  variables {
    services = {
      orders = {
        database = {}
        secrets  = { API_KEY = "arn:aws:secretsmanager:eu-west-2:111111111111:secret:orders/api-key-AbCdEf:key::" }
      }
    }
  }

  assert {
    condition     = length(module.database) == 1 && output.services["orders"].database_public == false
    error_message = "the Aurora cluster must never be publicly accessible."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.database_from_service["orders"].security_group_id == "sg-0database00000000" &&
      aws_vpc_security_group_ingress_rule.database_from_service["orders"].referenced_security_group_id == aws_security_group.service["orders"].id &&
      aws_security_group.service["orders"].id != "sg-0database00000000" &&
      aws_vpc_security_group_ingress_rule.database_from_service["orders"].cidr_ipv4 == null &&
      aws_vpc_security_group_ingress_rule.database_from_service["orders"].from_port == 5432
    )
    error_message = "the database SG must admit 5432 only from the service SG (no CIDR ingress)."
  }

  # Execution role reads the RDS-managed secret and the bare ARN of the app
  # secret (JSON-key suffix stripped), and nothing else.
  assert {
    condition = toset([for s in jsondecode(aws_iam_role_policy.execution["orders"].policy).Statement : s.Resource if s.Sid == "ReadOwnSecrets"][0]) == toset([
      "arn:aws:secretsmanager:eu-west-2:111111111111:secret:orders/api-key-AbCdEf",
      "arn:aws:secretsmanager:eu-west-2:111111111111:secret:rds!cluster-abc-AbCdEf",
    ])
    error_message = "the execution role must read only the service's own secrets."
  }
}

# ── Internet-facing ALB with HTTPS + redirect ──────────────────────────────

run "https_listener_with_redirect" {
  command = plan

  variables {
    alb_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/abc"
    services            = { orders = {} }
  }

  assert {
    condition     = toset(keys(module.alb[0].listener_arns)) == toset(["http", "https"]) && length(aws_vpc_security_group_ingress_rule.alb) == 2
    error_message = "a certificate must add an HTTPS listener (HTTP redirects) and open both ports to the ingress CIDRs."
  }
}
