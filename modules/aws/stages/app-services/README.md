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


- resource.aws_cloudwatch_log_group.service (modules/aws/stages/app-services/main.tf#L195)
- resource.aws_ecs_cluster.this (modules/aws/stages/app-services/main.tf#L157)
- resource.aws_iam_openid_connect_provider.github (modules/aws/stages/app-services/main.tf#L142)
- resource.aws_iam_role.deploy (modules/aws/stages/app-services/main.tf#L349)
- resource.aws_iam_role.execution (modules/aws/stages/app-services/main.tf#L224)
- resource.aws_iam_role.task (modules/aws/stages/app-services/main.tf#L294)
- resource.aws_iam_role_policy.deploy (modules/aws/stages/app-services/main.tf#L378)
- resource.aws_iam_role_policy.execution (modules/aws/stages/app-services/main.tf#L235)
- resource.aws_iam_role_policy.task (modules/aws/stages/app-services/main.tf#L305)
- resource.aws_iam_role_policy.task_exec (modules/aws/stages/app-services/main.tf#L313)
- resource.aws_iam_role_policy_attachment.task (modules/aws/stages/app-services/main.tf#L336)
- resource.aws_security_group.database (modules/aws/stages/app-services/main.tf#L506)
- resource.aws_security_group.service (modules/aws/stages/app-services/main.tf#L454)
- resource.aws_vpc_security_group_egress_rule.service_https (modules/aws/stages/app-services/main.tf#L478)
- resource.aws_vpc_security_group_egress_rule.service_to_db (modules/aws/stages/app-services/main.tf#L493)
- resource.aws_vpc_security_group_ingress_rule.alb (modules/aws/stages/app-services/main.tf#L439)
- resource.aws_vpc_security_group_ingress_rule.database_from_service (modules/aws/stages/app-services/main.tf#L518)
- resource.aws_vpc_security_group_ingress_rule.service_from_alb (modules/aws/stages/app-services/main.tf#L465)
- data source.aws_caller_identity.current (modules/aws/stages/app-services/main.tf#L134)
- data source.aws_partition.current (modules/aws/stages/app-services/main.tf#L130)


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
| <a name="input_bootstrap_image"></a> [bootstrap\_image](#input\_bootstrap\_image) | Placeholder image the FIRST task-definition revision of a service runs when its container\_image is null, so a first apply never references an image tag that does not exist yet. The default (NGINX unprivileged, ECR Public) listens on 8080 = the default container\_port and answers 200 on /, so the service turns healthy before the first CI deploy. Pulling it needs egress to ECR Public (the spoke's TGW default route to central egress); in a standalone spoke with no egress, set container\_image to an image in reach instead. | `string` | `"public.ecr.aws/nginx/nginx-unprivileged:stable-alpine"` | no |
| <a name="input_create_github_oidc_provider"></a> [create\_github\_oidc\_provider](#input\_create\_github\_oidc\_provider) | Create the account-wide GitHub OIDC provider in this module. Default false: in baselined member accounts the tfc-oidc-baseline StackSet owns it and the apply boundary denies iam:CreateOpenIDConnectProvider. Set true only in an account outside that baseline. | `bool` | `false` | no |
| <a name="input_database_subnet_ids"></a> [database\_subnet\_ids](#input\_database\_subnet\_ids) | Subnet IDs for Aurora DB subnet groups (aws-workload stage subnet\_ids\_by\_tier["isolated"] — no route off the VPC). At least two when any service enables a database. | `list(string)` | `[]` | no |
| <a name="input_enable_alarms"></a> [enable\_alarms](#input\_enable\_alarms) | Create per-service CloudWatch alarms (CPU, memory, unhealthy targets, target 5xx). Only takes effect when services is non-empty. | `bool` | `true` | no |
| <a name="input_enable_github_oidc"></a> [enable\_github\_oidc](#input\_enable\_github\_oidc) | Enable GitHub Actions OIDC deploy roles for services that set github. The roles trust the account's token.actions.githubusercontent.com provider, which the tfc-oidc-baseline StackSet creates (create\_github\_oidc\_provider there); set create\_github\_oidc\_provider here only for accounts outside that baseline. | `bool` | `false` | no |
| <a name="input_github_oidc_provider_arn"></a> [github\_oidc\_provider\_arn](#input\_github\_oidc\_provider\_arn) | ARN of the existing token.actions.githubusercontent.com OIDC provider. Null (default) derives this account's provider ARN (arn:<partition>:iam::<account>:oidc-provider/token.actions.githubusercontent.com), the one the tfc-oidc-baseline StackSet creates. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Customer-managed KMS key ARN encrypting the ECR repositories, CloudWatch log groups, Aurora storage, Performance Insights and the RDS-managed master secret. Required when services is non-empty. Its key policy must allow logs.<region>.amazonaws.com (log groups) and the ECS task execution roles (kms:Decrypt for secrets). | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention (days) of each service's CloudWatch log group. | `number` | `365` | no |
| <a name="input_service_subnet_ids"></a> [service\_subnet\_ids](#input\_service\_subnet\_ids) | PRIVATE subnet IDs the Fargate tasks run in (aws-workload stage subnet\_ids\_by\_tier["private"]). At least two (distinct AZs) when services is non-empty. | `list(string)` | `[]` | no |
| <a name="input_services"></a> [services](#input\_services) | Services to run, keyed by service name (lowercase, starts with a letter,<br/>letters/digits/hyphens). Each entry gets: an ECR repository (immutable tags,<br/>scan on push, KMS), a KMS-encrypted CloudWatch log group, least-privilege<br/>task execution + task roles, a Fargate service in the private subnets behind<br/>the shared ALB, and optionally a GitHub Actions deploy role (github) and an<br/>Aurora PostgreSQL cluster (database). Empty (default) creates nothing.<br/><br/>github OIDC subject precedence:<br/>  1. github.subject — an exact sub for any other customised claim template.<br/>  2. github.repository\_id + github.repository\_owner\_id (RECOMMENDED default<br/>     when set) — immutable numeric IDs, so renaming/transferring a repo or<br/>     re-creating a deleted name cannot inherit the trust:<br/>       repository\_owner\_id:<owner\_id>:repository\_id:<repo\_id>:environment:<env><br/>     (or :ref:<ref> when ref is set). Requires a ONE-TIME customisation of<br/>     the repo's sub claim template:<br/>       gh api -X PUT repos/<org>/<repo>/actions/oidc/customization/sub \<br/>         -F use\_default=false \<br/>         -f 'include\_claim\_keys[]=repository\_owner\_id' \<br/>         -f 'include\_claim\_keys[]=repository\_id' \<br/>         -f 'include\_claim\_keys[]=context'<br/>     IDs: gh api repos/<org>/<repo> --jq '.owner.id, .id'.<br/>  3. Fallback: repo:<repository>:environment:<environment> (or :ref:<ref>) —<br/>     the default GitHub template; name-based, so mutable. | <pre>map(object({<br/>    # Image the FIRST task-definition revision runs. null => the public<br/>    # placeholder bootstrap_image (listens on 8080); the first CI deploy<br/>    # replaces it with an image from the service's own ECR repo.<br/>    container_image  = optional(string)<br/>    container_port   = optional(number, 8080)<br/>    cpu              = optional(number, 256)<br/>    memory           = optional(number, 512)<br/>    cpu_architecture = optional(string, "X86_64")<br/>    desired_count    = optional(number, 2)<br/><br/>    # ALB routing on the shared listener. Both empty => path /<name> and /<name>/*.<br/>    host_headers      = optional(list(string), [])<br/>    path_patterns     = optional(list(string), [])<br/>    priority          = optional(number) # null => 1000 + index; explicit must be 1-999<br/>    health_check_path = optional(string, "/")<br/><br/>    environment = optional(map(string), {}) # plaintext, non-secret only<br/>    secrets     = optional(map(string), {}) # env var name => Secrets Manager / SSM ARN<br/><br/>    # Extra permissions for the application (task role). Never the deploy role.<br/>    task_role_policy_json         = optional(string)<br/>    task_role_managed_policy_arns = optional(list(string), [])<br/><br/>    enable_execute_command   = optional(bool, false)<br/>    enable_autoscaling       = optional(bool, false)<br/>    autoscaling_min_capacity = optional(number, 2)<br/>    autoscaling_max_capacity = optional(number, 10)<br/><br/>    # GitHub Actions deploy role (requires enable_github_oidc). null => none.<br/>    github = optional(object({<br/>      repository  = string           # "<org>/<repo>"<br/>      environment = optional(string) # GitHub environment; null => var.environment<br/>      ref         = optional(string) # e.g. refs/heads/main; used instead of environment<br/>      subject     = optional(string) # exact sub for a customised claim template<br/><br/>      # Immutable numeric IDs (set both): switches the sub to the ID-based<br/>      # customised template. See the description for the one-time gh setup.<br/>      repository_id       = optional(string)<br/>      repository_owner_id = optional(string)<br/>    }))<br/><br/>    # Aurora PostgreSQL for this service. null => none.<br/>    database = optional(object({<br/>      engine_version          = optional(string, "16.6")<br/>      instance_class          = optional(string, "db.r6g.large")<br/>      instance_count          = optional(number, 2)<br/>      enable_serverless_v2    = optional(bool, true)<br/>      serverless_min_capacity = optional(number, 0.5)<br/>      serverless_max_capacity = optional(number, 4)<br/>      database_name           = optional(string) # null => service name, hyphens replaced by underscores<br/>      backup_retention_period = optional(number, 7)<br/>      deletion_protection     = optional(bool, true)<br/>      skip_final_snapshot     = optional(bool, false)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags merged onto every resource (in addition to the provider default\_tags). | `map(string)` | `{}` | no |
| <a name="input_tfc_apply_boundary_policy_name"></a> [tfc\_apply\_boundary\_policy\_name](#input\_tfc\_apply\_boundary\_policy\_name) | Name of the tfc-apply permissions-boundary managed policy (tfc-oidc-baseline apply\_boundary\_policy\_name). Every IAM role this stage creates gets permissions\_boundary = arn:PARTITION:iam::ACCOUNT\_ID:policy/NAME, derived from the workload-account provider, which the member-account tfc-apply role requires when boundary propagation is on. Null = create roles without a boundary. | `string` | `"tfc-apply-boundary"` | no |
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
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | CMK encrypting every service's ECR repository, log group, Aurora cluster and RDS master secret, or null when services is empty. |
| <a name="output_services"></a> [services](#output\_services) | Per-service deployment contract: everything a CI pipeline needs (ECR repo, deploy role, cluster/service, task-definition family, container name) plus the runtime roles, log group and optional database endpoint/secret. |
<!-- END_TF_DOCS -->
