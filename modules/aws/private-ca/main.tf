# Centralized ACM Private CA hierarchy for the SRA landing zone.
#
# Provisions a single ACM Private Certificate Authority (ROOT or SUBORDINATE)
# and, optionally, shares it across the AWS organization via RAM so member
# accounts can issue certificates from one CA instead of standing up their own.
# One shared CA is materially cheaper than a per-account CA fleet: ACM PCA bills
# a fixed monthly charge per CA regardless of usage.
#
# The module is GATED (enable_private_ca defaults to false) precisely because a
# CA incurs that monthly charge from the moment it is created. Nothing is billed
# while the module is disabled.

resource "aws_acmpca_certificate_authority" "this" {
  count = var.enable_private_ca ? 1 : 0
  type  = var.ca_type

  certificate_authority_configuration {
    key_algorithm     = var.key_algorithm
    signing_algorithm = var.signing_algorithm

    subject {
      common_name = var.common_name
    }
  }

  # 7..30 day window before a deleted CA is permanently destroyed; keeps a
  # recovery window without forcing the maximum 30-day retention cost.
  permanent_deletion_time_in_days = var.permanent_deletion_time_in_days
}

# RAM share: created only when both the module is enabled and org sharing is on.
# allow_external_principals is hard-coded false so the CA can never be shared
# outside the organization.
resource "aws_ram_resource_share" "this" {
  count                     = var.enable_private_ca && var.share_org ? 1 : 0
  name                      = var.share_name
  allow_external_principals = false
}

resource "aws_ram_resource_association" "ca" {
  count              = var.enable_private_ca && var.share_org ? 1 : 0
  resource_arn       = aws_acmpca_certificate_authority.this[0].arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

resource "aws_ram_principal_association" "org" {
  count              = var.enable_private_ca && var.share_org ? 1 : 0
  principal          = var.org_arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}
