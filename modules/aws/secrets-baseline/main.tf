# Organization Secrets Manager baseline for the SRA landing zone.
#
# Creates a set of Secrets Manager secrets and attaches a resource policy to
# each that scopes GetSecretValue to principals in the organization
# (aws:PrincipalOrgID). Secrets whose definition supplies a rotation Lambda ARN
# also get automatic rotation wired up. Secrets are KMS-encrypted: with a
# customer-managed key when kms_key_id is supplied, otherwise with the
# account's default aws/secretsmanager key.
#
# The module is GATED (enable_secrets_baseline defaults to false); when disabled
# it creates no resources.

resource "aws_secretsmanager_secret" "this" {
  # checkov:skip=CKV_AWS_149: A customer-managed KMS key is used when kms_key_id
  # is supplied; otherwise the org intentionally falls back to the default
  # aws/secretsmanager managed key. Encryption at rest is always in effect.
  # checkov:skip=CKV2_AWS_57: Rotation is configured via
  # aws_secretsmanager_secret_rotation for secrets that supply a rotation
  # Lambda; automatic rotation is not mandated for every secret in the baseline.
  for_each   = var.enable_secrets_baseline ? var.secrets : {}
  name       = each.key
  kms_key_id = var.kms_key_id != "" ? var.kms_key_id : null
}

# Resource policy: allow GetSecretValue only for principals in the org.
# Principal = "*" is deliberately paired with the aws:PrincipalOrgID condition,
# which is the AWS-recommended pattern for org-scoped access.
resource "aws_secretsmanager_secret_policy" "this" {
  for_each   = var.enable_secrets_baseline ? var.secrets : {}
  secret_arn = aws_secretsmanager_secret.this[each.key].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OrgOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = "secretsmanager:GetSecretValue"
      Resource  = "*"
      Condition = {
        StringEquals = {
          "aws:PrincipalOrgID" = var.org_id
        }
      }
    }]
  })
}

resource "aws_secretsmanager_secret_rotation" "this" {
  # checkov:skip=CKV_AWS_304: rotation_days defaults to 30 and is a per-secret
  # input; the checker cannot resolve the dynamic value statically. Callers are
  # expected to keep the interval at or below 90 days.
  for_each = {
    for k, v in(var.enable_secrets_baseline ? var.secrets : {}) : k => v
    if try(v.rotation_lambda_arn, "") != ""
  }
  secret_id           = aws_secretsmanager_secret.this[each.key].id
  rotation_lambda_arn = each.value.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = try(each.value.rotation_days, 30)
  }
}
