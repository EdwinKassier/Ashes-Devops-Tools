# Security Lake metastore-manager role (security-tooling account).
#
# Security Lake runs a Lambda as this role to maintain the Lake Formation
# metastore. It used to be a hand-made prerequisite, so the default production
# profile failed to plan on an untouched fork. With meta_store_manager_role_arn
# left empty, the stage creates it here, carrying the tfc-apply boundary like
# every other role it creates in this account.

locals {
  create_meta_store_role = var.enable_security_lake && var.meta_store_manager_role_arn == ""
  meta_store_manager_role_arn = (
    local.create_meta_store_role ? aws_iam_role.securitylake_meta_store[0].arn : var.meta_store_manager_role_arn
  )
}

resource "aws_iam_role" "securitylake_meta_store" {
  count    = local.create_meta_store_role ? 1 : 0
  provider = aws.security_tooling

  name = "AmazonSecurityLakeMetaStoreManagerV2"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowLambda"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.security_tooling_account_id } }
    }]
  })
  permissions_boundary = local.security_tooling_boundary_arn
}

resource "aws_iam_role_policy_attachment" "securitylake_meta_store" {
  count    = local.create_meta_store_role ? 1 : 0
  provider = aws.security_tooling

  role       = aws_iam_role.securitylake_meta_store[0].name
  policy_arn = "arn:${can(regex("^aws(-[a-z]+)*$", local.boundary_partition)) ? local.boundary_partition : "aws"}:iam::aws:policy/service-role/AmazonSecurityLakeMetastoreManager"
}
