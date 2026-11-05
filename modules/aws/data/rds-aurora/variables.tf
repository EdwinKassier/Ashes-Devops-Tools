variable "name" {
  description = "Cluster identifier. Also used to derive the DB subnet group name and the default final snapshot identifier."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "name must start with a letter, be 1-63 characters, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "engine_version" {
  description = "aurora-postgresql engine version (e.g. 16.6)."
  type        = string
  default     = "16.6"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must look like <major>.<minor> (e.g. 16.6)."
  }
}

variable "instance_class" {
  description = "Instance class for the cluster instances. Ignored when enable_serverless_v2 is true (db.serverless is used instead)."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "instance_class must be a valid RDS instance class beginning with db. (e.g. db.r6g.large)."
  }
}

variable "instance_count" {
  description = "Number of cluster instances (writer + readers). Defaults to 2 for HA (one writer, one reader)."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 16
    error_message = "instance_count must be between 1 and 16."
  }
}

# ── Encryption (CMEK — required, no default AWS key) ───────────────────────────

variable "kms_key_id" {
  description = "Customer-managed KMS key ARN used to encrypt cluster storage (required — the default AWS-managed key is deliberately not allowed)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:kms:", var.kms_key_id))
    error_message = "kms_key_id must be a customer-managed KMS key ARN beginning with arn:aws:kms:."
  }
}

variable "performance_insights_kms_key_arn" {
  description = "KMS key ARN encrypting Performance Insights data. Defaults to kms_key_id when empty."
  type        = string
  default     = ""

  validation {
    condition     = var.performance_insights_kms_key_arn == "" || can(regex("^arn:aws:kms:", var.performance_insights_kms_key_arn))
    error_message = "performance_insights_kms_key_arn must be empty or a KMS key ARN beginning with arn:aws:kms:."
  }
}

# ── Networking (private) ──────────────────────────────────────────────────────

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group. These MUST be PRIVATE subnets — the cluster is never publicly accessible."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two private subnets (in distinct AZs) for an HA cluster."
  }
}

variable "security_group_ids" {
  description = "VPC security group IDs controlling network access to the cluster."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "security_group_ids must contain at least one security group ID."
  }
}

variable "port" {
  description = "TCP port the database listens on."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be between 1150 and 65535."
  }
}

# ── Database / credentials ────────────────────────────────────────────────────

variable "database_name" {
  description = "Name of the initial database created in the cluster."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, digits, and underscores (max 63 chars)."
  }
}

variable "master_username" {
  description = "Master (admin) username for the cluster."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must start with a letter and contain only letters, digits, and underscores."
  }
}

variable "manage_master_user_password" {
  description = "When true (default), RDS generates and manages the master password in Secrets Manager so it is never written to Terraform state. When false, master_password must be supplied."
  type        = bool
  default     = true
}

variable "master_password" {
  description = "Master password. Only used when manage_master_user_password is false; written with the write-only master_password_wo argument so it never enters plan or state. Prefer manage_master_user_password = true (RDS-managed secret)."
  type        = string
  default     = null
  sensitive   = true

  # Cross-variable validation (Terraform 1.9+): if RDS is not managing the
  # password, one must be supplied here.
  validation {
    condition     = var.manage_master_user_password || var.master_password != null
    error_message = "master_password must be set when manage_master_user_password is false."
  }
}

variable "master_user_secret_kms_key_id" {
  description = "KMS key ARN that encrypts the RDS-managed master user secret. Empty uses the default aws/secretsmanager key. Only used when manage_master_user_password is true."
  type        = string
  default     = ""

  validation {
    condition     = var.master_user_secret_kms_key_id == "" || can(regex("^arn:aws:kms:", var.master_user_secret_kms_key_id))
    error_message = "master_user_secret_kms_key_id must be empty or a KMS key ARN beginning with arn:aws:kms:."
  }
}

variable "iam_database_authentication_enabled" {
  description = "Whether to enable IAM database authentication."
  type        = bool
  default     = true
}

# ── Backups / protection ──────────────────────────────────────────────────────

variable "backup_retention_period" {
  description = "Number of days automated backups are retained."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Daily time range (UTC) during which automated backups are taken (hh24:mi-hh24:mi)."
  type        = string
  default     = "02:00-03:00"

  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.preferred_backup_window))
    error_message = "preferred_backup_window must be in hh24:mi-hh24:mi format (e.g. 02:00-03:00)."
  }
}

variable "preferred_maintenance_window" {
  description = "Weekly time range (UTC) for system maintenance (ddd:hh24:mi-ddd:hh24:mi)."
  type        = string
  default     = "sun:04:00-sun:05:00"

  validation {
    condition     = can(regex("^[a-z]{3}:[0-2][0-9]:[0-5][0-9]-[a-z]{3}:[0-2][0-9]:[0-5][0-9]$", var.preferred_maintenance_window))
    error_message = "preferred_maintenance_window must be in ddd:hh24:mi-ddd:hh24:mi format (e.g. sun:04:00-sun:05:00)."
  }
}

variable "deletion_protection" {
  description = "Whether the cluster has AWS-side deletion protection. Secure default is true; a terraform_data guard additionally blocks accidental `terraform destroy`."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot on cluster deletion. Secure default is false so a snapshot is always taken."
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "Identifier for the final snapshot taken on deletion. Defaults to <name>-final when empty. Ignored when skip_final_snapshot is true."
  type        = string
  default     = ""
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Log types to export to CloudWatch Logs (e.g. postgresql)."
  type        = list(string)
  default     = ["postgresql"]
}

variable "apply_immediately" {
  description = "Whether modifications are applied immediately rather than during the next maintenance window."
  type        = bool
  default     = false
}

# ── Serverless v2 (optional) ──────────────────────────────────────────────────

variable "enable_serverless_v2" {
  description = "Whether to run the cluster as Aurora Serverless v2 (engine_mode provisioned + serverlessv2_scaling_configuration, instances use db.serverless)."
  type        = bool
  default     = false
}

variable "serverless_v2_min_capacity" {
  description = "Minimum Aurora Capacity Units (ACU) for Serverless v2. Only used when enable_serverless_v2 is true."
  type        = number
  default     = 0.5

  validation {
    condition     = var.serverless_v2_min_capacity >= 0 && var.serverless_v2_min_capacity <= 256
    error_message = "serverless_v2_min_capacity must be between 0 and 256 ACU."
  }
}

variable "serverless_v2_max_capacity" {
  description = "Maximum Aurora Capacity Units (ACU) for Serverless v2. Only used when enable_serverless_v2 is true."
  type        = number
  default     = 4

  validation {
    condition     = var.serverless_v2_max_capacity >= 0.5 && var.serverless_v2_max_capacity <= 256
    error_message = "serverless_v2_max_capacity must be between 0.5 and 256 ACU."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 = disabled, the default). Set to 1/5/10/15/30/60 to enable; requires monitoring_role_arn."
  type        = number
  default     = 0
}

variable "monitoring_role_arn" {
  description = "IAM role ARN RDS uses for enhanced monitoring. Required when monitoring_interval > 0."
  type        = string
  default     = ""
}

variable "master_password_version" {
  description = "Write-only version counter for master_password (only used when manage_master_user_password is false). Increment to rotate the password."
  type        = number
  default     = 1

  validation {
    condition     = var.master_password_version >= 1 && floor(var.master_password_version) == var.master_password_version
    error_message = "master_password_version must be a positive integer."
  }
}
