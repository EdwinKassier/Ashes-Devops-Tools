# CloudTrail -> CloudWatch Logs delivery role for the organization trail
# (management account). Created here, by the phase-0 admin, so the
# least-privilege aws-security management role needs no IAM write: in the
# management account every role write is an escalation path (create or edit a
# role, give it admin, assume it, then OrganizationAccountAccessRole).

resource "aws_iam_role" "org_trail_cloudwatch" {
  count = var.create_org_trail_delivery_role ? 1 : 0

  name = "${var.org_trail_name}-cloudwatch-delivery"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = module.organization.management_account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "org_trail_cloudwatch" {
  count = var.create_org_trail_delivery_role ? 1 : 0

  name = "cloudwatch-logs-delivery"
  role = aws_iam_role.org_trail_cloudwatch[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:${var.partition}:logs:*:${module.organization.management_account_id}:log-group:/aws/cloudtrail/${var.org_trail_name}:*"
    }]
  })
}
