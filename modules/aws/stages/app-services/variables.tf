# -----------------------------------------------------------------------------
# Placement — the workload spoke this stage deploys into
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (dev, staging, prod, ...). Prefixes every resource name (cluster <environment>-apps, roles <environment>-<service>-*) and is the default GitHub Actions environment in each deploy role's OIDC subject."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.environment))
    error_message = "environment must be a lowercase name (letters, digits, hyphens; max 31 chars)."
  }
}

variable "aws_region" {
  description = "AWS region the services run in (awslogs-region for the container log driver)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "vpc_id" {
  description = "ID of the workload spoke VPC (aws-workload stage output vpc_id). Required when services is non-empty."
  type        = string
  default     = null

  validation {
    condition     = length(var.services) == 0 || can(regex("^vpc-", coalesce(var.vpc_id, "x")))
    error_message = "vpc_id must be a VPC id (vpc-...) when services is non-empty."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the spoke VPC. The default source of alb_ingress_cidrs (an internal ALB reachable from inside the spoke)."
  type        = string
  default     = "10.0.0.0/8"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "service_subnet_ids" {
  description = "PRIVATE subnet IDs the Fargate tasks run in (aws-workload stage subnet_ids_by_tier[\"private\"]). At least two (distinct AZs) when services is non-empty."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.services) == 0 || length(var.service_subnet_ids) >= 2
    error_message = "service_subnet_ids must contain at least two private subnets (distinct AZs) when services is non-empty."
  }
}

variable "alb_subnet_ids" {
  description = "Subnet IDs for the shared ALB. Empty uses service_subnet_ids (an internal ALB in the private tier). An internet-facing ALB (alb_internal = false) needs PUBLIC subnets here."
  type        = list(string)
  default     = []
}

variable "database_subnet_ids" {
  description = "Subnet IDs for Aurora DB subnet groups (aws-workload stage subnet_ids_by_tier[\"isolated\"] — no route off the VPC). At least two when any service enables a database."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in values(var.services) : s.database == null]) || length(var.database_subnet_ids) >= 2
    error_message = "database_subnet_ids must contain at least two subnets (distinct AZs) when any service sets database."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN encrypting the ECR repositories, CloudWatch log groups, Aurora storage, Performance Insights and the RDS-managed master secret. Required when services is non-empty. Its key policy must allow logs.<region>.amazonaws.com (log groups) and the ECS task execution roles (kms:Decrypt for secrets)."
  type        = string
  default     = ""

  validation {
    condition     = length(var.services) == 0 || can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a customer-managed KMS key ARN (arn:aws:kms:...) when services is non-empty."
  }
}

# -----------------------------------------------------------------------------
# Services — the golden path. One map entry = one deployable service.
# -----------------------------------------------------------------------------

variable "services" {
  description = <<-EOT
    Services to run, keyed by service name (lowercase, starts with a letter,
    letters/digits/hyphens). Each entry gets: an ECR repository (immutable tags,
    scan on push, KMS), a KMS-encrypted CloudWatch log group, least-privilege
    task execution + task roles, a Fargate service in the private subnets behind
    the shared ALB, and optionally a GitHub Actions deploy role (github) and an
    Aurora PostgreSQL cluster (database). Empty (default) creates nothing.

    github OIDC subject precedence:
      1. github.subject — an exact sub for any other customised claim template.
      2. github.repository_id + github.repository_owner_id (RECOMMENDED default
         when set) — immutable numeric IDs, so renaming/transferring a repo or
         re-creating a deleted name cannot inherit the trust:
           repository_owner_id:<owner_id>:repository_id:<repo_id>:environment:<env>
         (or :ref:<ref> when ref is set). Requires a ONE-TIME customisation of
         the repo's sub claim template:
           gh api -X PUT repos/<org>/<repo>/actions/oidc/customization/sub \
             -F use_default=false \
             -f 'include_claim_keys[]=repository_owner_id' \
             -f 'include_claim_keys[]=repository_id' \
             -f 'include_claim_keys[]=context'
         IDs: gh api repos/<org>/<repo> --jq '.owner.id, .id'.
      3. Fallback: repo:<repository>:environment:<environment> (or :ref:<ref>) —
         the default GitHub template; name-based, so mutable.
  EOT
  type = map(object({
    # Image the FIRST task-definition revision runs. null => <ecr-repo>:bootstrap
    # (push that tag once, or let the first CI deploy replace it).
    container_image  = optional(string)
    container_port   = optional(number, 8080)
    cpu              = optional(number, 256)
    memory           = optional(number, 512)
    cpu_architecture = optional(string, "X86_64")
    desired_count    = optional(number, 2)

    # ALB routing on the shared listener. Both empty => path /<name> and /<name>/*.
    host_headers      = optional(list(string), [])
    path_patterns     = optional(list(string), [])
    priority          = optional(number) # null => 1000 + index; explicit must be 1-999
    health_check_path = optional(string, "/")

    environment = optional(map(string), {}) # plaintext, non-secret only
    secrets     = optional(map(string), {}) # env var name => Secrets Manager / SSM ARN

    # Extra permissions for the application (task role). Never the deploy role.
    task_role_policy_json         = optional(string)
    task_role_managed_policy_arns = optional(list(string), [])

    enable_execute_command   = optional(bool, false)
    enable_autoscaling       = optional(bool, false)
    autoscaling_min_capacity = optional(number, 2)
    autoscaling_max_capacity = optional(number, 10)

    # GitHub Actions deploy role (requires enable_github_oidc). null => none.
    github = optional(object({
      repository  = string           # "<org>/<repo>"
      environment = optional(string) # GitHub environment; null => var.environment
      ref         = optional(string) # e.g. refs/heads/main; used instead of environment
      subject     = optional(string) # exact sub for a customised claim template

      # Immutable numeric IDs (set both): switches the sub to the ID-based
      # customised template. See the description for the one-time gh setup.
      repository_id       = optional(string)
      repository_owner_id = optional(string)
    }))

    # Aurora PostgreSQL for this service. null => none.
    database = optional(object({
      engine_version          = optional(string, "16.6")
      instance_class          = optional(string, "db.r6g.large")
      instance_count          = optional(number, 2)
      enable_serverless_v2    = optional(bool, true)
      serverless_min_capacity = optional(number, 0.5)
      serverless_max_capacity = optional(number, 4)
      database_name           = optional(string) # null => service name, hyphens replaced by underscores
      backup_retention_period = optional(number, 7)
      deletion_protection     = optional(bool, true)
      skip_final_snapshot     = optional(bool, false)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.services) : can(regex("^[a-z][a-z0-9-]{0,22}$", k))])
    error_message = "services keys must be lowercase, start with a letter, and be 1-23 chars of letters, digits or hyphens."
  }

  validation {
    # Target-group names are <environment>-<service> and capped at 32 chars.
    condition     = alltrue([for k in keys(var.services) : length(var.environment) + 1 + length(k) <= 32])
    error_message = "length(environment) + 1 + length(service key) must be <= 32 (ALB target group name limit)."
  }

  validation {
    condition = alltrue([
      for s in values(var.services) : s.github == null || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", s.github.repository))
    ])
    error_message = "services[*].github.repository must be \"<org>/<repo>\"."
  }

  validation {
    # The OIDC subject is matched with StringEquals: wildcards would widen trust
    # to every repo/branch they match, so they are rejected outright.
    condition = alltrue([
      for s in values(var.services) : s.github == null || (
        !can(regex("[*?]", coalesce(s.github.subject, "x"))) &&
        !can(regex("[*?]", coalesce(s.github.ref, "x"))) &&
        !can(regex("[*?]", coalesce(s.github.environment, "x")))
      )
    ])
    error_message = "services[*].github subject/ref/environment must not contain wildcards (* or ?) — deploy-role trust is an exact match."
  }

  validation {
    condition = alltrue([
      for s in values(var.services) : s.github == null || (
        (s.github.repository_id == null) == (s.github.repository_owner_id == null) &&
        (s.github.repository_id == null || can(regex("^[0-9]{1,20}$", coalesce(s.github.repository_id, "x")))) &&
        (s.github.repository_owner_id == null || can(regex("^[0-9]{1,20}$", coalesce(s.github.repository_owner_id, "x"))))
      )
    ])
    error_message = "services[*].github.repository_id and repository_owner_id must be set together, as numeric GitHub IDs (gh api repos/<org>/<repo> --jq '.owner.id, .id')."
  }

  validation {
    condition = alltrue([
      for s in values(var.services) : s.github == null || s.github.ref == null || startswith(coalesce(s.github.ref, "x"), "refs/")
    ])
    error_message = "services[*].github.ref must be a full ref, e.g. refs/heads/main or refs/tags/v1.0.0."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : s.priority == null || (coalesce(s.priority, 1) >= 1 && coalesce(s.priority, 1) <= 999)])
    error_message = "services[*].priority must be 1-999 (1000+ is reserved for auto-assigned rule priorities)."
  }

  validation {
    condition = alltrue(flatten([
      for s in values(var.services) : [for arn in values(s.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):", arn))]
    ]))
    error_message = "services[*].secrets values must be Secrets Manager or SSM Parameter Store ARNs — never plaintext."
  }
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC
# -----------------------------------------------------------------------------

variable "enable_github_oidc" {
  description = "Enable GitHub Actions OIDC deploy roles for services that set github. Also creates the account's token.actions.githubusercontent.com OIDC provider unless create_github_oidc_provider is false."
  type        = bool
  default     = false
}

variable "create_github_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider (one per account per URL). Set false when another root already owns it and pass github_oidc_provider_arn."
  type        = bool
  default     = true

  validation {
    condition     = !var.enable_github_oidc || var.create_github_oidc_provider || var.github_oidc_provider_arn != null
    error_message = "github_oidc_provider_arn is required when enable_github_oidc = true and create_github_oidc_provider = false."
  }
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing token.actions.githubusercontent.com OIDC provider, used when create_github_oidc_provider is false."
  type        = string
  default     = null

  validation {
    condition     = var.github_oidc_provider_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", coalesce(var.github_oidc_provider_arn, "x")))
    error_message = "github_oidc_provider_arn must be an IAM OIDC provider ARN for token.actions.githubusercontent.com."
  }
}

# -----------------------------------------------------------------------------
# Shared ALB
# -----------------------------------------------------------------------------

variable "alb_internal" {
  description = "Whether the shared ALB is internal (default; reachable from the spoke and, via the TGW, the rest of the org). Internet exposure belongs at the edge (CloudFront + WAF); an internet-facing ALB here also needs public alb_subnet_ids."
  type        = bool
  default     = true
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for an HTTPS :443 listener (HTTP :80 then redirects to it). null serves plain HTTP :80 — acceptable only for an internal ALB inside the private network."
  type        = string
  default     = null

  validation {
    condition     = var.alb_certificate_arn == null || can(regex("^arn:aws[a-z-]*:acm:", coalesce(var.alb_certificate_arn, "x")))
    error_message = "alb_certificate_arn must be null or an ACM certificate ARN."
  }

  validation {
    condition     = var.alb_internal || var.alb_certificate_arn != null
    error_message = "An internet-facing ALB (alb_internal = false) requires alb_certificate_arn (no plaintext HTTP on the internet)."
  }
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB listeners. Empty uses [vpc_cidr]."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.alb_ingress_cidrs : can(cidrnetmask(c))])
    error_message = "alb_ingress_cidrs entries must be valid IPv4 CIDR blocks."
  }
}

variable "alb_enable_deletion_protection" {
  description = "Deletion protection on the shared ALB. Set false only for ephemeral environments."
  type        = bool
  default     = true
}

variable "alb_access_logs_bucket" {
  description = "S3 bucket for ALB access logs (prefix alb/<environment>). null disables access logging. The bucket policy must allow the regional ELB log-delivery principal."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Logs + alarms
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Retention (days) of each service's CloudWatch log group."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value (e.g. 30, 90, 365)."
  }
}

variable "enable_alarms" {
  description = "Create per-service CloudWatch alarms (CPU, memory, unhealthy targets, target 5xx). Only takes effect when services is non-empty."
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm / OK notifications. null creates the alarms with no notification action."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags merged onto every resource (in addition to the provider default_tags)."
  type        = map(string)
  default     = {}
}
