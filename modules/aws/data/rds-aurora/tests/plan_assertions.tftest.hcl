# Resource-assertion tests for the aws/data/rds-aurora module.
#
# Asserts on configured attributes known at plan time under mock_provider —
# the secure defaults (encryption, no public access, deletion protection, IAM
# auth, managed password) and the serverless-v2 toggle.

mock_provider "aws" {}

variables {
  name               = "orders-db"
  kms_key_id         = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  subnet_ids         = ["subnet-0aaa", "subnet-0bbb"]
  security_group_ids = ["sg-0aaa"]
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.engine == "aurora-postgresql"
    error_message = "cluster must use the aurora-postgresql engine."
  }

  assert {
    condition     = aws_rds_cluster.this.storage_encrypted == true
    error_message = "cluster storage must be encrypted."
  }

  assert {
    condition     = aws_rds_cluster.this.kms_key_id == var.kms_key_id
    error_message = "cluster must be encrypted with the supplied customer-managed KMS key."
  }

  assert {
    condition     = aws_rds_cluster.this.deletion_protection == true
    error_message = "deletion_protection must default to true."
  }

  assert {
    condition     = aws_rds_cluster.this.iam_database_authentication_enabled == true
    error_message = "IAM database authentication must default to on."
  }

  assert {
    condition     = aws_rds_cluster.this.manage_master_user_password == true
    error_message = "master password must be managed by RDS (Secrets Manager) by default."
  }

  assert {
    condition     = aws_rds_cluster.this.backup_retention_period == 7
    error_message = "backup_retention_period must default to 7 days."
  }

  assert {
    condition     = aws_rds_cluster.this.copy_tags_to_snapshot == true
    error_message = "copy_tags_to_snapshot must be enabled."
  }

  # HA: default of 2 instances.
  assert {
    condition     = length(aws_rds_cluster_instance.this) == var.instance_count
    error_message = "one cluster instance must be created per instance_count."
  }

  assert {
    condition     = length(aws_rds_cluster_instance.this) == 2
    error_message = "the default instance_count must produce 2 instances for HA."
  }

  assert {
    condition     = aws_rds_cluster_instance.this[0].publicly_accessible == false
    error_message = "cluster instances must never be publicly accessible."
  }

  assert {
    condition     = aws_rds_cluster_instance.this[0].performance_insights_enabled == true
    error_message = "Performance Insights must be enabled on cluster instances."
  }

  assert {
    condition     = aws_rds_cluster_instance.this[0].performance_insights_kms_key_id == var.kms_key_id
    error_message = "Performance Insights must be encrypted with the CMEK (defaulting to kms_key_id)."
  }

  # No serverless scaling block by default.
  assert {
    condition     = length(aws_rds_cluster.this.serverlessv2_scaling_configuration) == 0
    error_message = "no serverlessv2 scaling configuration must be present by default."
  }

  # Deletion guard present.
  assert {
    condition     = terraform_data.deletion_guard[0].input == var.name
    error_message = "the deletion guard must track the cluster identifier."
  }
}

run "serverless_v2_enabled" {
  command = plan

  variables {
    enable_serverless_v2       = true
    serverless_v2_min_capacity = 1
    serverless_v2_max_capacity = 8
  }

  assert {
    condition     = length(aws_rds_cluster.this.serverlessv2_scaling_configuration) == 1
    error_message = "a serverlessv2 scaling configuration must be present when enable_serverless_v2 is true."
  }

  assert {
    condition     = aws_rds_cluster.this.engine_mode == "provisioned"
    error_message = "serverless v2 must keep engine_mode provisioned."
  }

  assert {
    condition     = aws_rds_cluster_instance.this[0].instance_class == "db.serverless"
    error_message = "serverless v2 instances must use the db.serverless class."
  }
}

run "unmanaged_password_path" {
  command = plan

  variables {
    manage_master_user_password = false
    master_password             = "aVerySecretValue123!"
  }

  assert {
    condition     = aws_rds_cluster.this.manage_master_user_password == null || aws_rds_cluster.this.manage_master_user_password == false
    error_message = "manage_master_user_password must be off when a password is supplied."
  }

  assert {
    condition     = output.master_user_secret_arn == null
    error_message = "master_user_secret_arn output must be null when the password is not RDS-managed."
  }
}
