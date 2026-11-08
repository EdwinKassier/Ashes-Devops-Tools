# Basic working example for the aws/app-services stage (the AWS application
# golden path). Deploys one service, "orders", into a workload spoke: an ECR
# repository, a KMS-encrypted log group, least-privilege task roles, a Fargate
# service in PRIVATE subnets behind the shared INTERNAL ALB (HTTPS with an HTTP
# redirect), a GitHub Actions deploy role pinned to immutable repository IDs,
# an Aurora PostgreSQL Serverless v2 cluster in ISOLATED subnets, and CloudWatch
# alarms on a KMS-encrypted SNS topic. One customer-managed KMS key encrypts
# everything. Run `terraform init && terraform validate` here to check it.
#
# In a real landing zone envs/aws/workload composes this stage from the
# aws-workload outputs (vpc_id, subnet_ids_by_tier, the workload CMK). Every ID
# and ARN below is a placeholder: replace them with your own.

module "app_services" {
  source = "../../"

  environment = "dev"
  aws_region  = "eu-west-2"

  vpc_id              = "vpc-0123456789abcdef0"
  vpc_cidr            = "10.20.0.0/16"
  service_subnet_ids  = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"] # private tier
  database_subnet_ids = ["subnet-0ddddddddddddddd1", "subnet-0ddddddddddddddd2"] # isolated tier
  kms_key_arn         = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"

  alb_certificate_arn    = "arn:aws:acm:eu-west-2:111122223333:certificate/11111111-2222-3333-4444-555555555555"
  alb_access_logs_bucket = "example-alb-access-logs"

  # The account's GitHub OIDC provider comes from the tfc-oidc-baseline StackSet.
  enable_github_oidc = true

  services = {
    orders = {
      container_port    = 8080
      health_check_path = "/healthz"

      environment = {
        LOG_LEVEL = "info"
      }
      secrets = {
        STRIPE_API_KEY = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:dev/orders/stripe-AbCdEf"
      }

      github = {
        repository = "example-org/orders"
        # Immutable numeric IDs (gh api repos/<org>/<repo> --jq '.owner.id, .id');
        # needs the one-time sub claim customisation described in the README.
        repository_owner_id = "1234567"
        repository_id       = "765432100"
      }

      database = {
        enable_serverless_v2 = true
      }
    }
  }

  tags = {
    environment = "dev"
  }
}
