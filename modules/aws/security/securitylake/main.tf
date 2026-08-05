# Amazon Security Lake — centralized OCSF security-data lake for the SRA landing
# zone. Runs in the delegated-administrator (Security Tooling) account, so no
# cross-account (aliased) provider is needed here.

resource "aws_securitylake_data_lake" "this" {
  count = var.enable_security_lake ? 1 : 0

  meta_store_manager_role_arn = var.meta_store_manager_role_arn

  dynamic "configuration" {
    for_each = toset(var.aws_enabled_regions)

    content {
      region = configuration.value

      # encryption_configuration is a nested attribute (list of object) in the
      # aws provider, NOT a block — set it with assignment syntax.
      encryption_configuration = [{
        kms_key_id = var.kms_key_id
      }]
    }
  }
}

resource "aws_securitylake_aws_log_source" "this" {
  for_each = var.enable_security_lake ? toset(var.log_sources) : []

  source {
    source_name = each.value # CLOUD_TRAIL_MGMT | VPC_FLOW | ROUTE53 | SH_FINDINGS
    regions     = var.aws_enabled_regions
  }

  depends_on = [aws_securitylake_data_lake.this]
}

resource "aws_securitylake_subscriber" "this" {
  count = var.enable_security_lake && var.subscriber_principal != "" ? 1 : 0

  subscriber_name = var.subscriber_name

  source {
    aws_log_source_resource {
      source_name    = "CLOUD_TRAIL_MGMT"
      source_version = "2.0"
    }
  }

  subscriber_identity {
    external_id = var.subscriber_external_id
    principal   = var.subscriber_principal
  }

  depends_on = [aws_securitylake_aws_log_source.this]
}
