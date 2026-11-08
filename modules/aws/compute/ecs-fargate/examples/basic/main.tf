# Basic working example for the aws/ecs-fargate module.
# Runs one Fargate service on a module-created cluster, in private subnets with
# no public IP, behind an existing ALB target group. Logs are encrypted with a
# customer-managed KMS key and the database password is injected from Secrets
# Manager (never a plaintext value). Run `terraform init && terraform validate`
# here to check it.
#
# Every ID and ARN below is a placeholder: replace them with your own private
# subnets, task security group, least-privilege IAM roles, target group and CMK.

module "ecs_fargate" {
  source = "../../"

  name           = "orders-api"
  region         = "eu-west-2"
  family         = "dev-orders-api"
  create_cluster = true

  container_image = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/orders-api:1.0.0"
  container_port  = 8080
  cpu             = 512
  memory          = 1024

  container_environment = [
    { name = "LOG_LEVEL", value = "info" },
  ]
  container_secrets = [
    { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:dev/orders-api/db-AbCdEf" },
  ]

  # Private subnets only; assign_public_ip stays at its secure default (false).
  subnets            = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  security_group_ids = ["sg-0bbbbbbbbbbbbbbb1"]

  execution_role_arn = "arn:aws:iam::111122223333:role/dev-orders-api-execution"
  task_role_arn      = "arn:aws:iam::111122223333:role/dev-orders-api-task"

  target_group_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/dev-orders-api/0123456789abcdef"

  log_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"

  # Let a CI pipeline (e.g. GitHub Actions) register new task-definition
  # revisions without Terraform reverting each deploy.
  enable_external_deployments = true

  tags = {
    environment = "dev"
  }
}
