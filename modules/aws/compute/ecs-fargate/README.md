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


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	container_image = 
	execution_role_arn = 
	family = 
	name = 
	region = 
	security_group_ids = 
	subnets = 
	task_role_arn = 
	
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


- resource.aws_appautoscaling_policy.cpu (modules/aws/compute/ecs-fargate/main.tf#L220)
- resource.aws_appautoscaling_target.this (modules/aws/compute/ecs-fargate/main.tf#L210)
- resource.aws_cloudwatch_log_group.this (modules/aws/compute/ecs-fargate/main.tf#L76)
- resource.aws_ecs_cluster.this (modules/aws/compute/ecs-fargate/main.tf#L61)
- resource.aws_ecs_service.externally_deployed (modules/aws/compute/ecs-fargate/main.tf#L156)
- resource.aws_ecs_service.this (modules/aws/compute/ecs-fargate/main.tf#L118)
- resource.aws_ecs_task_definition.this (modules/aws/compute/ecs-fargate/main.tf#L88)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_container_image"></a> [container\_image](#input\_container\_image) | Container image reference (repository:tag or image digest) for the primary container. | `string` | n/a | yes |
| <a name="input_execution_role_arn"></a> [execution\_role\_arn](#input\_execution\_role\_arn) | ARN of the task execution role (pulls images, writes logs, reads secrets). Least-privilege scoping is the caller's responsibility. | `string` | n/a | yes |
| <a name="input_family"></a> [family](#input\_family) | Family name for the task definition. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the ECS service. Also used as the default prefix for the log group and (when created) the ECS cluster. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region, used to build the awslogs-region for the container log driver. | `string` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security group IDs attached to the task ENIs. | `list(string)` | n/a | yes |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Subnet IDs the Fargate tasks run in. These MUST be PRIVATE subnets. | `list(string)` | n/a | yes |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | ARN of the task role assumed by the application containers. Least-privilege scoping is the caller's responsibility. | `string` | n/a | yes |
| <a name="input_assign_public_ip"></a> [assign\_public\_ip](#input\_assign\_public\_ip) | Whether to assign a public IP to task ENIs. Secure default is false — tasks run in private subnets behind NAT/an ALB. | `bool` | `false` | no |
| <a name="input_autoscaling_max_capacity"></a> [autoscaling\_max\_capacity](#input\_autoscaling\_max\_capacity) | Maximum task count when autoscaling is enabled. | `number` | `10` | no |
| <a name="input_autoscaling_min_capacity"></a> [autoscaling\_min\_capacity](#input\_autoscaling\_min\_capacity) | Minimum task count when autoscaling is enabled. | `number` | `2` | no |
| <a name="input_autoscaling_target_cpu"></a> [autoscaling\_target\_cpu](#input\_autoscaling\_target\_cpu) | Target average CPU utilization (percent) for the target-tracking scaling policy. | `number` | `70` | no |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of an existing ECS cluster to run the service in. Required when create\_cluster is false; ignored when create\_cluster is true. | `string` | `""` | no |
| <a name="input_container_environment"></a> [container\_environment](#input\_container\_environment) | Plaintext environment variables for the container (non-secret values only). Each entry is { name, value }. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_container_name"></a> [container\_name](#input\_container\_name) | Name of the primary container. Defaults to the service name when left empty. | `string` | `""` | no |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | Port the primary container listens on (also the ALB target port when a target group is attached). | `number` | `8080` | no |
| <a name="input_container_secrets"></a> [container\_secrets](#input\_container\_secrets) | Secret environment variables injected via valueFrom. Each valueFrom MUST be a Secrets Manager or SSM Parameter Store ARN — never a plaintext value. Each entry is { name, valueFrom }. | <pre>list(object({<br/>    name      = string<br/>    valueFrom = string<br/>  }))</pre> | `[]` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task-level CPU units (Fargate). Must be a valid Fargate CPU value. | `number` | `256` | no |
| <a name="input_cpu_architecture"></a> [cpu\_architecture](#input\_cpu\_architecture) | Fargate runtime CPU architecture for the task. | `string` | `"X86_64"` | no |
| <a name="input_create_cluster"></a> [create\_cluster](#input\_create\_cluster) | Whether this module creates the ECS cluster (with Container Insights enabled). When false, cluster\_arn must reference an existing cluster. | `bool` | `false` | no |
| <a name="input_create_log_group"></a> [create\_log\_group](#input\_create\_log\_group) | Whether this module creates the CloudWatch log group for container logs. When false, log\_group\_name must reference an existing group. | `bool` | `true` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Number of task copies the service keeps running. | `number` | `2` | no |
| <a name="input_enable_autoscaling"></a> [enable\_autoscaling](#input\_enable\_autoscaling) | Whether to create Application Auto Scaling target + target-tracking policy for the service. | `bool` | `false` | no |
| <a name="input_enable_deployment_circuit_breaker"></a> [enable\_deployment\_circuit\_breaker](#input\_enable\_deployment\_circuit\_breaker) | Enable the ECS deployment circuit breaker with automatic rollback, so a revision whose tasks never become healthy is rolled back instead of looping. | `bool` | `true` | no |
| <a name="input_enable_execute_command"></a> [enable\_execute\_command](#input\_enable\_execute\_command) | Whether to enable ECS Exec (interactive shell into running tasks). Secure default is false. | `bool` | `false` | no |
| <a name="input_enable_external_deployments"></a> [enable\_external\_deployments](#input\_enable\_external\_deployments) | Hand task-definition rollouts to an external pipeline (e.g. GitHub Actions RegisterTaskDefinition + UpdateService): Terraform still creates the initial revision and the service, but ignores later task\_definition and desired\_count drift instead of reverting each deploy. | `bool` | `false` | no |
| <a name="input_health_check_grace_period_seconds"></a> [health\_check\_grace\_period\_seconds](#input\_health\_check\_grace\_period\_seconds) | Grace period before the service starts health-checking newly started tasks. Only applied when a target group is attached. | `number` | `60` | no |
| <a name="input_load_balancer_container_port"></a> [load\_balancer\_container\_port](#input\_load\_balancer\_container\_port) | Container port registered with the target group. Defaults to container\_port when null. | `number` | `null` | no |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | CloudWatch log group name for container logs. Defaults to /ecs/<family> when empty. | `string` | `""` | no |
| <a name="input_log_kms_key_arn"></a> [log\_kms\_key\_arn](#input\_log\_kms\_key\_arn) | Optional KMS key ARN to encrypt the container log group. Empty string uses the default CloudWatch encryption. | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention (days) for the container log group when created by this module. | `number` | `365` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Task-level memory (MiB, Fargate). Must be compatible with the chosen cpu value. | `number` | `512` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |
| <a name="input_target_group_arn"></a> [target\_group\_arn](#input\_target\_group\_arn) | ALB/NLB target group ARN to register tasks with. Empty string disables load balancer attachment. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the cluster the service runs in (created here or passed in). |
| <a name="output_container_name"></a> [container\_name](#output\_container\_name) | Name of the primary container (the container CI rewrites the image of). |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the CloudWatch log group container logs are shipped to. |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | ARN of the ECS service. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ECS service. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the task definition revision the service runs. |
| <a name="output_task_definition_family"></a> [task\_definition\_family](#output\_task\_definition\_family) | Family of the task definition (CI registers new revisions in this family). |
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
