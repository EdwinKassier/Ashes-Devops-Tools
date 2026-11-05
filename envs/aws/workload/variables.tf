# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization + aws-network workspaces it reads. Supplied to the backend via backend.hcl / TF_CLI_ARGS_init (kept out of the code so the same root works across orgs and CI)."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads account_role_arns from."
  type        = string
  default     = "aws-organization"
}

variable "network_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-2 aws-network root state that this root reads the network cross-root contract (tgw_id, ipam_pool_ids) from."
  type        = string
  default     = "aws-network"
}

variable "workload_account_key" {
  description = "Key into the aws-organization root's account_role_arns map identifying THIS environment's workload account (e.g. \"workload_dev\"). Both the default and us_east_1 providers assume that role."
  type        = string

  validation {
    condition     = length(trimspace(var.workload_account_key)) > 0
    error_message = "workload_account_key must be a non-empty account_role_arns map key."
  }
}

# -----------------------------------------------------------------------------
# Region + addressing
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region the workload's spoke VPC is deployed in and the region the default provider assumes the workload-account role in. Also the key used to select the regional IPAM pool from the aws-network contract."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "aws_enabled_regions" {
  description = "Regions in which to enforce the account baseline and deploy a Config recorder. Defaults to the single home Region."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one region."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the workload spoke VPC. Used for subnet math; the actual CIDR is allocated from the shared IPAM pool at apply."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.20.0.0/16)."
  }
}

# -----------------------------------------------------------------------------
# Log-archive naming contract + Config + KMS + toggles
# -----------------------------------------------------------------------------

variable "log_archive_bucket_name" {
  description = "Name of the central log-archive bucket (receives this workload's VPC flow logs, Config snapshots/history, and Session Manager logs). Default null sources it from the aws-security root's remote state (its owner — see audit M7), so a rename there flows through automatically. Set a value only to override for an out-of-band setup."
  type        = string
  default     = null

  validation {
    condition     = var.log_archive_bucket_name == null || length(trimspace(coalesce(var.log_archive_bucket_name, " "))) > 0
    error_message = "log_archive_bucket_name must be null (source from aws-security) or a non-empty S3 bucket name."
  }
}

variable "security_workspace_name" {
  description = "Name of the aws-security TFC workspace, read via remote state for the central log-archive bucket name (audit M7)."
  type        = string
  default     = "aws-security"
}

variable "config_role_arn" {
  description = "ARN of the IAM role AWS Config assumes to record resource configurations in this workload account/Region."
  type        = string

  validation {
    condition     = length(trimspace(var.config_role_arn)) > 0
    error_message = "config_role_arn must be a non-empty IAM role ARN."
  }
}

variable "kms_key_arn" {
  description = "ARN of the CMK used as the account default EBS encryption key and to encrypt Session Manager sessions/logs. Also encrypts the app-services ECR repos, log groups, Aurora clusters and RDS master secrets (required when services is non-empty; its key policy must admit logs.<region>.amazonaws.com). Empty string leaves default EBS encryption on the AWS-managed key."
  type        = string
  default     = ""
}

variable "enable_edge" {
  description = "Deploy the per-workload edge-security stack (CloudFront + WAF, in us-east-1). Off by default; opt in when this environment fronts an internet-facing app."
  type        = bool
  default     = false
}

variable "workload_roles" {
  description = "Map of workload / cross-account IAM role name to its configuration (trust_policy JSON, managed_policy_arns, inline_policy, etc.). Empty by default."
  type = map(object({
    trust_policy         = string
    max_session_duration = optional(number, 3600)
    managed_policy_arns  = optional(list(string), [])
    inline_policy        = optional(string, "")
    permissions_boundary = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# SaaS secret bridge (audit H9, hybrid option C) — AWS counterpart to the GCP one.
#
# Opt-in. When enabled, this workload reads the Supabase outputs from a saas-<name>
# workspace and writes them into an AWS Secrets Manager secret, so an ECS/Fargate
# task can consume Supabase as a managed datastore via the container secrets
# valueFrom. Default off: no SaaS coupling, and the workload reads no saas state.
#
# NOTE: the bridged values (service role key, database password) are stored as a
# secret version, so they persist in THIS root's state as well as the saas root's.
# Teams that require zero secret duplication should create the secret out of band
# and leave this bridge disabled.
# -----------------------------------------------------------------------------

variable "enable_saas_secret_bridge" {
  description = "Bridge Supabase connection details from a saas-<name> workspace into an AWS Secrets Manager secret (opt-in, audit H9). Default false."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_saas_secret_bridge || (var.saas_workspace_name != null && length(var.saas_secret_reader_arns) > 0)
    error_message = "enable_saas_secret_bridge = true requires saas_workspace_name and at least one saas_secret_reader_arns entry (the task role that reads the secret)."
  }
}

variable "saas_workspace_name" {
  description = "TFC workspace (saas-<name>) to read Supabase outputs from when enable_saas_secret_bridge is true."
  type        = string
  default     = null
}

variable "saas_secret_name" {
  description = "Name of the Secrets Manager secret that holds the bridged Supabase connection JSON (api_url, service_role_key, database_password)."
  type        = string
  default     = "supabase-connection"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,512}$", var.saas_secret_name))
    error_message = "saas_secret_name must be a valid Secrets Manager name (1-512 chars of alphanumerics and /_+=.@-)."
  }
}

variable "saas_secret_reader_arns" {
  description = "IAM principal ARNs granted secretsmanager:GetSecretValue on the bridged secret (e.g. the ECS task role). Required when the bridge is enabled."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.saas_secret_reader_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:", a))])
    error_message = "Each saas_secret_reader_arns entry must be an account-qualified IAM ARN (arn:aws:iam::<12-digit>:...)."
  }
}

# -----------------------------------------------------------------------------
# Tagging — provider default_tags (FinOps / governance)
#
# Every resource the aws provider(s) in this root create gets the canonical tag
# set: CostCenter / Environment / Owner (the keys the tag policy enforces and
# cost-governance activates as cost-allocation tags) plus ManagedBy /
# LandingZone / Workspace. default_tags is merged LAST, so it can add keys or
# override any canonical value.
# -----------------------------------------------------------------------------

variable "landing_zone_name" {
  description = "Landing-zone identifier written to the LandingZone tag on every resource."
  type        = string
  default     = "ashes"

  validation {
    condition     = length(trimspace(var.landing_zone_name)) > 0
    error_message = "landing_zone_name must be a non-empty string."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter cost-allocation tag on every resource in this root."
  type        = string
  default     = "platform"

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "cost_center must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag on every resource in this root (team or distribution list)."
  type        = string
  default     = "platform-team"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "default_tags" {
  description = "Extra tags merged into the aws provider default_tags (after the canonical set, so they may override it). Values must be non-empty."
  type        = map(string)
  default     = {}

  validation {
    # An empty-string default tag makes the provider plan a perpetual diff.
    condition     = alltrue([for v in values(var.default_tags) : length(trimspace(v)) > 0])
    error_message = "default_tags values must be non-empty strings."
  }
}

variable "environment" {
  description = "Environment this workload root serves (dev, staging, prod, ...). Drives the Environment tag, the Workspace tag (aws-workload-<environment>) and the spoke name (workload-<environment>). null derives it from workload_account_key by stripping a leading \"workload_\" / \"workload-\" (e.g. workload_dev -> dev)."
  type        = string
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z][a-z0-9-]{0,30}$", coalesce(var.environment, "x")))
    error_message = "environment must be null or a lowercase name (letters, digits, hyphens; max 31 chars)."
  }
}

variable "tgw_route_tiers" {
  description = "Spoke subnet tiers whose route tables send tgw_destination_cidrs to the shared transit gateway."
  type        = list(string)
  default     = ["private"]
}

variable "tgw_destination_cidrs" {
  description = "Destination CIDRs routed from tgw_route_tiers to the shared transit gateway. Default 0.0.0.0/0 (centralized egress + inspection via the hub); use the org supernet for east-west only."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# Credentials
# -----------------------------------------------------------------------------

variable "assume_role_arn" {
  description = "Optional role the aws provider(s) assume. Default null: the workspace's TFC dynamic credentials (TFC_AWS_PROVIDER_AUTH + TFC_AWS_PLAN_ROLE_ARN / TFC_AWS_APPLY_ROLE_ARN, from the aws-organization outputs tfc_plan_role_arns / tfc_apply_role_arns) already resolve to the target member account, so no hop is made. Legacy / local runs from management-account credentials set this to the account's account_role_arns entry (OrganizationAccountAccessRole)."
  type        = string
  default     = null

  validation {
    condition     = var.assume_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.assume_role_arn, "x")))
    error_message = "assume_role_arn must be null or an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

# -----------------------------------------------------------------------------
# App services — the application golden path (modules/aws/stages/app-services)
#
# One entry in `services` = a deployable service in this workload account: ECR
# repo, Fargate service behind the shared internal ALB, least-privilege task
# roles, KMS log group, plus an optional GitHub Actions deploy role (github) and
# Aurora PostgreSQL cluster (database). Default {} creates nothing. Requires a
# non-empty kms_key_arn whose key policy admits CloudWatch Logs. See
# docs/guides/deploying-a-service.md (AWS section).
# -----------------------------------------------------------------------------

variable "services" {
  description = "Services to run in this environment, keyed by service name. Full field reference: modules/aws/stages/app-services (variable services). Empty (default) creates nothing."
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
    }))

    # Aurora PostgreSQL for this service. null => none.
    database = optional(object({
      engine_version          = optional(string, "16.6")
      instance_class          = optional(string, "db.r6g.large")
      instance_count          = optional(number, 2)
      enable_serverless_v2    = optional(bool, true)
      serverless_min_capacity = optional(number, 0.5)
      serverless_max_capacity = optional(number, 4)
      database_name           = optional(string) # null => service name with _ for -
      backup_retention_period = optional(number, 7)
      deletion_protection     = optional(bool, true)
      skip_final_snapshot     = optional(bool, false)
    }))
  }))
  default = {}
}

variable "enable_github_oidc" {
  description = "Create GitHub Actions OIDC deploy roles for services that set github (and the account's GitHub OIDC provider unless create_github_oidc_provider = false)."
  type        = bool
  default     = false
}

variable "create_github_oidc_provider" {
  description = "Create the account-wide token.actions.githubusercontent.com OIDC provider. Set false when it already exists in this account and pass github_oidc_provider_arn."
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing GitHub OIDC provider, used when create_github_oidc_provider = false."
  type        = string
  default     = null
}

variable "app_service_subnet_tier" {
  description = "Spoke subnet tier the Fargate tasks run in."
  type        = string
  default     = "private"
}

variable "app_alb_subnet_tier" {
  description = "Spoke subnet tier the shared ALB is placed in (private for the default internal ALB; a public tier only for an internet-facing ALB)."
  type        = string
  default     = "private"
}

variable "app_database_subnet_tier" {
  description = "Spoke subnet tier Aurora DB subnet groups use (isolated = no route off the VPC)."
  type        = string
  default     = "isolated"
}

variable "app_alb_internal" {
  description = "Whether the shared ALB is internal (default). Public exposure belongs at the edge (enable_edge); an internet-facing ALB needs a public subnet tier and app_alb_certificate_arn."
  type        = bool
  default     = true
}

variable "app_alb_certificate_arn" {
  description = "ACM certificate for an HTTPS :443 listener on the shared ALB (HTTP :80 then redirects). null serves HTTP :80 inside the private network only."
  type        = string
  default     = null
}

variable "app_alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the shared ALB. Empty uses [vpc_cidr]; add the org supernet to allow other spokes via the TGW."
  type        = list(string)
  default     = []
}

variable "app_alb_enable_deletion_protection" {
  description = "Deletion protection on the shared ALB. Set false only for ephemeral environments."
  type        = bool
  default     = true
}

variable "app_alb_access_logs_bucket" {
  description = "S3 bucket for ALB access logs, or null to disable."
  type        = string
  default     = null
}

variable "app_log_retention_days" {
  description = "Retention (days) for each service's CloudWatch log group."
  type        = number
  default     = 365
}

variable "enable_app_alarms" {
  description = "Create per-service CloudWatch alarms (CPU, memory, unhealthy targets, 5xx) when services is non-empty."
  type        = bool
  default     = true
}

variable "app_alarm_sns_topic_arn" {
  description = "SNS topic for app alarm notifications, or null for no notification action."
  type        = string
  default     = null
}
