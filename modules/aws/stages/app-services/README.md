# aws-app-services stage

The AWS **application golden path**: a service team adds one entry to `services`
in `aws-workload-<env>` and gets everything needed to build, deploy and run a
container in that environment's workload account. Composed from envs/aws/workload
via a single `module "app_services"` call. Default `services = {}` creates
nothing.

Per service:

| What | How |
|------|-----|
| ECR repository | `data/ecr` — IMMUTABLE tags, scan on push, workload CMK, lifecycle (untagged 7d, keep last 100) |
| Log group | `/ecs/<env>/<service>`, CMK-encrypted, `log_retention_days` |
| Task execution role | pull **its** repo, write **its** log group, read **its** secrets (+ `kms:Decrypt`) |
| Task role | empty by default — `task_role_policy_json` / `task_role_managed_policy_arns` |
| Fargate service | `compute/ecs-fargate` — private subnets, no public IP, circuit breaker + rollback, behind the shared ALB |
| Deploy role (opt) | `github` + `enable_github_oidc` — trust `aud = sts.amazonaws.com` AND an exact `sub`; push to its repo, `RegisterTaskDefinition`, `UpdateService` on its service, `iam:PassRole` on its two task roles to `ecs-tasks` only |
| Aurora PostgreSQL (opt) | `data/rds-aurora` — `database = {}`; RDS-managed master secret (CMK), isolated subnets, SG ingress 5432 from the service SG only; `DB_HOST/DB_PORT/DB_NAME` env + `DB_USERNAME/DB_PASSWORD` secrets injected |
| Alarms (opt) | `ops/cloudwatch` — CPU, memory, unhealthy targets, target 5xx |

Shared per environment (only when `services` is non-empty): ECS cluster
`<env>-apps` (Container Insights) and one ALB (`network/load-balancer`) —
**internal** by default, default action 404, one host/path rule per service
(default path `/<service>` and `/<service>/*`). With `alb_certificate_arn` the
ALB serves HTTPS :443 and redirects :80.

## GitHub OIDC subject

The deploy role trusts exactly one subject (StringEquals; wildcards rejected):

1. `github.subject` — verbatim, for repos with a **customised sub claim
   template** (e.g. `repository_owner_id` + `repository_id` + `environment`, or
   `job_workflow_ref`). IAM cannot condition on GitHub claims other than
   `sub`/`aud`, so immutable-ID or reusable-workflow pinning must be put INTO
   `sub` via the GitHub OIDC customisation API.
2. `github.ref` — `repo:<org>/<repo>:ref:<ref>`.
3. default — `repo:<org>/<repo>:environment:<github.environment or env>`.

A service with a deploy role is CI-owned: the ECS service ignores
`task_definition` / `desired_count` drift (`enable_external_deployments`), so
Terraform does not roll back pipeline deploys.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	aws_region =
	environment =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |

## Modules


- alarms - ../../ops/cloudwatch
- alb - ../../network/load-balancer
- database - ../../data/rds-aurora
- ecr - ../../data/ecr
- service - ../../compute/ecs-fargate


## Resources

The following resources are created:


- resource.aws_cloudwatch_log_group.service (modules/aws/stages/app-services/main.tf#L157)
- resource.aws_ecs_cluster.this (modules/aws/stages/app-services/main.tf#L119)
- resource.aws_iam_openid_connect_provider.github (modules/aws/stages/app-services/main.tf#L104)
- resource.aws_iam_role.deploy (modules/aws/stages/app-services/main.tf#L309)
- resource.aws_iam_role.execution (modules/aws/stages/app-services/main.tf#L186)
- resource.aws_iam_role.task (modules/aws/stages/app-services/main.tf#L255)
- resource.aws_iam_role_policy.deploy (modules/aws/stages/app-services/main.tf#L337)
- resource.aws_iam_role_policy.execution (modules/aws/stages/app-services/main.tf#L196)
- resource.aws_iam_role_policy.task (modules/aws/stages/app-services/main.tf#L265)
- resource.aws_iam_role_policy.task_exec (modules/aws/stages/app-services/main.tf#L273)
- resource.aws_iam_role_policy_attachment.task (modules/aws/stages/app-services/main.tf#L296)
- resource.aws_security_group.database (modules/aws/stages/app-services/main.tf#L465)
- resource.aws_security_group.service (modules/aws/stages/app-services/main.tf#L413)
- resource.aws_vpc_security_group_egress_rule.service_https (modules/aws/stages/app-services/main.tf#L437)
- resource.aws_vpc_security_group_egress_rule.service_to_db (modules/aws/stages/app-services/main.tf#L452)
- resource.aws_vpc_security_group_ingress_rule.alb (modules/aws/stages/app-services/main.tf#L398)
- resource.aws_vpc_security_group_ingress_rule.database_from_service (modules/aws/stages/app-services/main.tf#L477)
- resource.aws_vpc_security_group_ingress_rule.service_from_alb (modules/aws/stages/app-services/main.tf#L424)
- data source.aws_caller_identity.current (modules/aws/stages/app-services/main.tf#L96)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region the services run in (awslogs-region for the container log driver). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod, ...). Prefixes every resource name (cluster <environment>-apps, roles <environment>-<service>-*) and is the default GitHub Actions environment in each deploy role's OIDC subject. | `string` | n/a | yes |
| <a name="input_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#input\_alarm\_sns\_topic\_arn) | SNS topic ARN for alarm / OK notifications. null creates the alarms with no notification action. | `string` | `null` | no |
| <a name="input_alb_access_logs_bucket"></a> [alb\_access\_logs\_bucket](#input\_alb\_access\_logs\_bucket) | S3 bucket for ALB access logs (prefix alb/<environment>). null disables access logging. The bucket policy must allow the regional ELB log-delivery principal. | `string` | `null` | no |
| <a name="input_alb_certificate_arn"></a> [alb\_certificate\_arn](#input\_alb\_certificate\_arn) | ACM certificate ARN for an HTTPS :443 listener (HTTP :80 then redirects to it). null serves plain HTTP :80 — acceptable only for an internal ALB inside the private network. | `string` | `null` | no |
| <a name="input_alb_enable_deletion_protection"></a> [alb\_enable\_deletion\_protection](#input\_alb\_enable\_deletion\_protection) | Deletion protection on the shared ALB. Set false only for ephemeral environments. | `bool` | `true` | no |
| <a name="input_alb_ingress_cidrs"></a> [alb\_ingress\_cidrs](#input\_alb\_ingress\_cidrs) | CIDRs allowed to reach the ALB listeners. Empty uses [vpc\_cidr]. | `list(string)` | `[]` | no |
| <a name="input_alb_internal"></a> [alb\_internal](#input\_alb\_internal) | Whether the shared ALB is internal (default; reachable from the spoke and, via the TGW, the rest of the org). Internet exposure belongs at the edge (CloudFront + WAF); an internet-facing ALB here also needs public alb\_subnet\_ids. | `bool` | `true` | no |
| <a name="input_alb_subnet_ids"></a> [alb\_subnet\_ids](#input\_alb\_subnet\_ids) | Subnet IDs for the shared ALB. Empty uses service\_subnet\_ids (an internal ALB in the private tier). An internet-facing ALB (alb\_internal = false) needs PUBLIC subnets here. | `list(string)` | `[]` | no |
| <a name="input_create_github_oidc_provider"></a> [create\_github\_oidc\_provider](#input\_create\_github\_oidc\_provider) | Create the account-wide GitHub OIDC provider (one per account per URL). Set false when another root already owns it and pass github\_oidc\_provider\_arn. | `bool` | `true` | no |
| <a name="input_database_subnet_ids"></a> [database\_subnet\_ids](#input\_database\_subnet\_ids) | Subnet IDs for Aurora DB subnet groups (aws-workload stage subnet\_ids\_by\_tier["isolated"] — no route off the VPC). At least two when any service enables a database. | `list(string)` | `[]` | no |
| <a name="input_enable_alarms"></a> [enable\_alarms](#input\_enable\_alarms) | Create per-service CloudWatch alarms (CPU, memory, unhealthy targets, target 5xx). Only takes effect when services is non-empty. | `bool` | `true` | no |
| <a name="input_enable_github_oidc"></a> [enable\_github\_oidc](#input\_enable\_github\_oidc) | Enable GitHub Actions OIDC deploy roles for services that set github. Also creates the account's token.actions.githubusercontent.com OIDC provider unless create\_github\_oidc\_provider is false. | `bool` | `false` | no |
| <a name="input_github_oidc_provider_arn"></a> [github\_oidc\_provider\_arn](#input\_github\_oidc\_provider\_arn) | ARN of an existing token.actions.githubusercontent.com OIDC provider, used when create\_github\_oidc\_provider is false. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Customer-managed KMS key ARN encrypting the ECR repositories, CloudWatch log groups, Aurora storage, Performance Insights and the RDS-managed master secret. Required when services is non-empty. Its key policy must allow logs.<region>.amazonaws.com (log groups) and the ECS task execution roles (kms:Decrypt for secrets). | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention (days) of each service's CloudWatch log group. | `number` | `365` | no |
| <a name="input_service_subnet_ids"></a> [service\_subnet\_ids](#input\_service\_subnet\_ids) | PRIVATE subnet IDs the Fargate tasks run in (aws-workload stage subnet\_ids\_by\_tier["private"]). At least two (distinct AZs) when services is non-empty. | `list(string)` | `[]` | no |
| <a name="input_services"></a> [services](#input\_services) | Services to run, keyed by service name (lowercase, starts with a letter,<br/>letters/digits/hyphens). Each entry gets: an ECR repository (immutable tags,<br/>scan on push, KMS), a KMS-encrypted CloudWatch log group, least-privilege<br/>task execution + task roles, a Fargate service in the private subnets behind<br/>the shared ALB, and optionally a GitHub Actions deploy role (github) and an<br/>Aurora PostgreSQL cluster (database). Empty (default) creates nothing.<br/><br/>github.subject overrides the OIDC subject for repositories that use a<br/>customised sub claim template (e.g. one including repository\_id or<br/>job\_workflow\_ref); otherwise the subject is<br/>repo:<repository>:environment:<environment> (or :ref:<ref> when ref is set). | <pre>map(object({<br/>    # Image the FIRST task-definition revision runs. null => <ecr-repo>:bootstrap<br/>    # (push that tag once, or let the first CI deploy replace it).<br/>    container_image  = optional(string)<br/>    container_port   = optional(number, 8080)<br/>    cpu              = optional(number, 256)<br/>    memory           = optional(number, 512)<br/>    cpu_architecture = optional(string, "X86_64")<br/>    desired_count    = optional(number, 2)<br/><br/>    # ALB routing on the shared listener. Both empty => path /<name> and /<name>/*.<br/>    host_headers      = optional(list(string), [])<br/>    path_patterns     = optional(list(string), [])<br/>    priority          = optional(number) # null => 1000 + index; explicit must be 1-999<br/>    health_check_path = optional(string, "/")<br/><br/>    environment = optional(map(string), {}) # plaintext, non-secret only<br/>    secrets     = optional(map(string), {}) # env var name => Secrets Manager / SSM ARN<br/><br/>    # Extra permissions for the application (task role). Never the deploy role.<br/>    task_role_policy_json         = optional(string)<br/>    task_role_managed_policy_arns = optional(list(string), [])<br/><br/>    enable_execute_command   = optional(bool, false)<br/>    enable_autoscaling       = optional(bool, false)<br/>    autoscaling_min_capacity = optional(number, 2)<br/>    autoscaling_max_capacity = optional(number, 10)<br/><br/>    # GitHub Actions deploy role (requires enable_github_oidc). null => none.<br/>    github = optional(object({<br/>      repository  = string           # "<org>/<repo>"<br/>      environment = optional(string) # GitHub environment; null => var.environment<br/>      ref         = optional(string) # e.g. refs/heads/main; used instead of environment<br/>      subject     = optional(string) # exact sub for a customised claim template<br/>    }))<br/><br/>    # Aurora PostgreSQL for this service. null => none.<br/>    database = optional(object({<br/>      engine_version          = optional(string, "16.6")<br/>      instance_class          = optional(string, "db.r6g.large")<br/>      instance_count          = optional(number, 2)<br/>      enable_serverless_v2    = optional(bool, true)<br/>      serverless_min_capacity = optional(number, 0.5)<br/>      serverless_max_capacity = optional(number, 4)<br/>      database_name           = optional(string) # null => service name with_ for -<br/>      backup_retention_period = optional(number, 7)<br/>      deletion_protection     = optional(bool, true)<br/>      skip_final_snapshot     = optional(bool, false)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags merged onto every resource (in addition to the provider default\_tags). | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | IPv4 CIDR of the spoke VPC. The default source of alb\_ingress\_cidrs (an internal ALB reachable from inside the spoke). | `string` | `"10.0.0.0/8"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the workload spoke VPC (aws-workload stage output vpc\_id). Required when services is non-empty. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | ARN of the shared ALB, or null when services is empty. |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the shared ALB (internal by default), or null when services is empty. |
| <a name="output_alb_internal"></a> [alb\_internal](#output\_alb\_internal) | Whether the shared ALB is internal, or null when services is empty. |
| <a name="output_alb_security_group_id"></a> [alb\_security\_group\_id](#output\_alb\_security\_group\_id) | Security group of the shared ALB, or null when services is empty. |
| <a name="output_alb_zone_id"></a> [alb\_zone\_id](#output\_alb\_zone\_id) | Route 53 hosted zone ID of the shared ALB (for alias records), or null when services is empty. |
| <a name="output_ecs_cluster_arn"></a> [ecs\_cluster\_arn](#output\_ecs\_cluster\_arn) | ARN of the shared per-environment ECS cluster, or null when services is empty. |
| <a name="output_ecs_cluster_name"></a> [ecs\_cluster\_name](#output\_ecs\_cluster\_name) | Name of the shared per-environment ECS cluster, or null when services is empty. |
| <a name="output_github_oidc_provider_arn"></a> [github\_oidc\_provider\_arn](#output\_github\_oidc\_provider\_arn) | ARN of the GitHub Actions OIDC provider deploy roles trust (created here or passed in), or null when enable\_github\_oidc is false. |
| <a name="output_github_oidc_subjects"></a> [github\_oidc\_subjects](#output\_github\_oidc\_subjects) | Map of service name to the exact token.actions.githubusercontent.com:sub its deploy role trusts. |
| <a name="output_services"></a> [services](#output\_services) | Per-service deployment contract: everything a CI pipeline needs (ECR repo, deploy role, cluster/service, task-definition family, container name) plus the runtime roles, log group and optional database endpoint/secret. |
<!-- END_TF_DOCS -->
