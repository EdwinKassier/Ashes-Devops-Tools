# ecs-fargate

Containerized application runtime on ECS Fargate for the landing zone. Composes
an `aws_ecs_task_definition` and an `aws_ecs_service` (launch type `FARGATE`,
`awsvpc` network mode) with secure defaults: tasks run in **private** subnets
with **no public IP**, ECS Exec is **off**, and container secrets are injected
via `valueFrom` (Secrets Manager / SSM Parameter Store ARNs) so no secret
material is ever embedded in the task definition or Terraform state.

Everything is a toggle. The ECS cluster is either created here (`create_cluster`,
with Container Insights on) or passed in via `cluster_arn`. The CloudWatch log
group is created here (`create_log_group`, with retention + optional KMS) or
referenced by name. ALB/NLB registration (`target_group_arn`) and Application
Auto Scaling (`enable_autoscaling`, CPU target-tracking) are both opt-in.

IAM roles are accepted as ARNs (`execution_role_arn`, `task_role_arn`) —
least-privilege scoping is the caller's responsibility, so this module never
mints permissive roles.

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs output goes here — run `make docs` to regenerate -->
<!-- END_TF_DOCS -->

## Usage

```hcl
module "orders_api" {
  source = "../../modules/aws/compute/ecs-fargate"

  name               = "orders-api"
  region             = "eu-west-2"
  family             = "orders-api"
  create_cluster     = true
  container_image    = "123456789012.dkr.ecr.eu-west-2.amazonaws.com/orders:1.0.0"
  container_port     = 8080
  subnets            = module.vpc.subnet_ids_by_tier["private"]
  security_group_ids = [aws_security_group.orders.id]
  execution_role_arn = aws_iam_role.orders_exec.arn
  task_role_arn      = aws_iam_role.orders_task.arn

  container_secrets = [
    { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db.arn }
  ]

  target_group_arn   = aws_lb_target_group.orders.arn
  enable_autoscaling = true
}
```
