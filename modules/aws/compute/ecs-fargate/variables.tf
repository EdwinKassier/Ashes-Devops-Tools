variable "name" {
  description = "Name of the ECS service. Also used as the default prefix for the log group and (when created) the ECS cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.name))
    error_message = "name must be 1-255 characters and contain only letters, digits, underscores, and hyphens."
  }
}

variable "region" {
  description = "AWS region, used to build the awslogs-region for the container log driver."
  type        = string

  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "region must be a non-empty string."
  }
}

# ── Cluster ───────────────────────────────────────────────────────────────────

variable "create_cluster" {
  description = "Whether this module creates the ECS cluster (with Container Insights enabled). When false, cluster_arn must reference an existing cluster."
  type        = bool
  default     = false
}

variable "cluster_arn" {
  description = "ARN of an existing ECS cluster to run the service in. Required when create_cluster is false; ignored when create_cluster is true."
  type        = string
  default     = ""

  validation {
    condition     = var.cluster_arn == "" || can(regex("^arn:aws:ecs:", var.cluster_arn))
    error_message = "cluster_arn must be empty or a valid ECS cluster ARN beginning with arn:aws:ecs:."
  }
}

# ── Task definition ───────────────────────────────────────────────────────────

variable "family" {
  description = "Family name for the task definition."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.family))
    error_message = "family must be 1-255 characters and contain only letters, digits, underscores, and hyphens."
  }
}

variable "cpu" {
  description = "Task-level CPU units (Fargate). Must be a valid Fargate CPU value."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be one of the valid Fargate values: 256, 512, 1024, 2048, 4096, 8192, 16384."
  }
}

variable "memory" {
  description = "Task-level memory (MiB, Fargate). Must be compatible with the chosen cpu value."
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 122880
    error_message = "memory must be between 512 and 122880 MiB."
  }
}

variable "cpu_architecture" {
  description = "Fargate runtime CPU architecture for the task."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "container_name" {
  description = "Name of the primary container. Defaults to the service name when left empty."
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Container image reference (repository:tag or image digest) for the primary container."
  type        = string

  validation {
    condition     = length(trimspace(var.container_image)) > 0
    error_message = "container_image must be a non-empty string."
  }
}

variable "container_port" {
  description = "Port the primary container listens on (also the ALB target port when a target group is attached)."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "container_environment" {
  description = "Plaintext environment variables for the container (non-secret values only). Each entry is { name, value }."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "container_secrets" {
  description = "Secret environment variables injected via valueFrom. Each valueFrom MUST be a Secrets Manager or SSM Parameter Store ARN — never a plaintext value. Each entry is { name, valueFrom }."
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []

  validation {
    condition = alltrue([
      for s in var.container_secrets :
      can(regex("^arn:aws:(secretsmanager|ssm):", s.valueFrom))
    ])
    error_message = "Every container_secrets[*].valueFrom must be a Secrets Manager (arn:aws:secretsmanager:) or SSM (arn:aws:ssm:) ARN — plaintext secret values are not allowed."
  }
}

# ── Service / networking ──────────────────────────────────────────────────────

variable "desired_count" {
  description = "Number of task copies the service keeps running."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}

variable "subnets" {
  description = "Subnet IDs the Fargate tasks run in. These MUST be PRIVATE subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnets) > 0
    error_message = "subnets must contain at least one private subnet ID."
  }
}

variable "security_group_ids" {
  description = "Security group IDs attached to the task ENIs."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "security_group_ids must contain at least one security group ID."
  }
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to task ENIs. Secure default is false — tasks run in private subnets behind NAT/an ALB."
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Whether to enable ECS Exec (interactive shell into running tasks). Secure default is false."
  type        = bool
  default     = false
}

# ── IAM (caller-owned, least-privilege) ───────────────────────────────────────

variable "execution_role_arn" {
  description = "ARN of the task execution role (pulls images, writes logs, reads secrets). Least-privilege scoping is the caller's responsibility."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::", var.execution_role_arn))
    error_message = "execution_role_arn must be a valid IAM role ARN beginning with arn:aws:iam::."
  }
}

variable "task_role_arn" {
  description = "ARN of the task role assumed by the application containers. Least-privilege scoping is the caller's responsibility."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::", var.task_role_arn))
    error_message = "task_role_arn must be a valid IAM role ARN beginning with arn:aws:iam::."
  }
}

# ── Load balancer (optional) ──────────────────────────────────────────────────

variable "target_group_arn" {
  description = "ALB/NLB target group ARN to register tasks with. Empty string disables load balancer attachment."
  type        = string
  default     = ""

  validation {
    condition     = var.target_group_arn == "" || can(regex("^arn:aws:elasticloadbalancing:", var.target_group_arn))
    error_message = "target_group_arn must be empty or a valid target group ARN beginning with arn:aws:elasticloadbalancing:."
  }
}

variable "load_balancer_container_port" {
  description = "Container port registered with the target group. Defaults to container_port when null."
  type        = number
  default     = null
}

variable "health_check_grace_period_seconds" {
  description = "Grace period before the service starts health-checking newly started tasks. Only applied when a target group is attached."
  type        = number
  default     = 60

  validation {
    condition     = var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647
    error_message = "health_check_grace_period_seconds must be zero or greater."
  }
}

# ── Logging ───────────────────────────────────────────────────────────────────

variable "create_log_group" {
  description = "Whether this module creates the CloudWatch log group for container logs. When false, log_group_name must reference an existing group."
  type        = bool
  default     = true
}

variable "log_group_name" {
  description = "CloudWatch log group name for container logs. Defaults to /ecs/<family> when empty."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Retention (days) for the container log group when created by this module."
  type        = number
  default     = 365

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value (e.g. 7, 30, 90, 365)."
  }
}

variable "log_kms_key_arn" {
  description = "Optional KMS key ARN to encrypt the container log group. Empty string uses the default CloudWatch encryption."
  type        = string
  default     = ""

  validation {
    condition     = var.log_kms_key_arn == "" || can(regex("^arn:aws:kms:", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be empty or a valid KMS key ARN beginning with arn:aws:kms:."
  }
}

# ── Autoscaling (optional) ────────────────────────────────────────────────────

variable "enable_autoscaling" {
  description = "Whether to create Application Auto Scaling target + target-tracking policy for the service."
  type        = bool
  default     = false
}

variable "autoscaling_min_capacity" {
  description = "Minimum task count when autoscaling is enabled."
  type        = number
  default     = 2

  validation {
    condition     = var.autoscaling_min_capacity >= 0
    error_message = "autoscaling_min_capacity must be zero or greater."
  }
}

variable "autoscaling_max_capacity" {
  description = "Maximum task count when autoscaling is enabled."
  type        = number
  default     = 10

  validation {
    condition     = var.autoscaling_max_capacity >= 1
    error_message = "autoscaling_max_capacity must be at least 1."
  }
}

variable "autoscaling_target_cpu" {
  description = "Target average CPU utilization (percent) for the target-tracking scaling policy."
  type        = number
  default     = 70

  validation {
    condition     = var.autoscaling_target_cpu > 0 && var.autoscaling_target_cpu <= 100
    error_message = "autoscaling_target_cpu must be between 1 and 100."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
