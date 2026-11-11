# Amazon Security Lake — centralized OCSF security-data lake for the SRA landing
# zone. Runs in the delegated-administrator (Security Tooling) account, so no
# cross-account (aliased) provider is needed here.

# The provider allows one configuration block per data lake, so each enabled
# Region gets its own data lake. The first Region of aws_enabled_regions is the
# home Region (this[0], unchanged address); the others use the provider-v6
# per-resource region argument. A KMS key is regional: the home key encrypts
# the home lake only, and each other Region takes its key from
# additional_region_kms_key_ids (S3_MANAGED when absent).
locals {
  home_region        = var.aws_enabled_regions[0]
  additional_regions = var.enable_security_lake ? toset(slice(var.aws_enabled_regions, 1, length(var.aws_enabled_regions))) : toset([])
}

resource "aws_securitylake_data_lake" "this" {
  count = var.enable_security_lake ? 1 : 0

  meta_store_manager_role_arn = var.meta_store_manager_role_arn

  configuration {
    region = local.home_region

    # encryption_configuration is a nested attribute (list of object) in the
    # aws provider, NOT a block — set it with assignment syntax.
    encryption_configuration = [{
      kms_key_id = var.kms_key_id
    }]
  }

  tags = var.tags
}

resource "aws_securitylake_data_lake" "additional" {
  for_each = local.additional_regions

  region                      = each.value
  meta_store_manager_role_arn = var.meta_store_manager_role_arn

  configuration {
    region = each.value

    encryption_configuration = [{
      kms_key_id = lookup(var.additional_region_kms_key_ids, each.value, "S3_MANAGED")
    }]
  }

  tags = var.tags
}

resource "aws_securitylake_aws_log_source" "this" {
  for_each = var.enable_security_lake ? toset(var.log_sources) : []

  source {
    source_name = each.value # CLOUD_TRAIL_MGMT | VPC_FLOW | ROUTE53 | SH_FINDINGS
    regions     = var.aws_enabled_regions
  }

  depends_on = [aws_securitylake_data_lake.this, aws_securitylake_data_lake.additional]
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

  tags = var.tags

  depends_on = [aws_securitylake_aws_log_source.this]
}
