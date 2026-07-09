# AWS incident-response automation for the SRA landing zone.
#
# Wires GuardDuty high-severity findings to an automated isolation Lambda and
# provisions an intra-org forensics role for cross-account EBS-snapshot sharing.
# The whole module is gated behind enable_incident_response so it can be safely
# included in stages that do not yet run incident response.
#
# Flow: GuardDuty -> EventBridge rule (severity >= 7) -> EventBridge target ->
# isolation Lambda. The Lambda ships as a scaffold (see files/isolate.py);
# extend it to attach a quarantine SG and drive snapshot forensics.

# Package the Lambda source. The archive provider runs locally at plan time and
# writes files/isolate.zip; that artifact is a build output and is not tracked.
data "archive_file" "isolate" {
  count       = var.enable_incident_response ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/files/isolate.py"
  output_path = "${path.module}/files/isolate.zip"
}

# Execution role for the isolation Lambda.
resource "aws_iam_role" "isolation_lambda" {
  count = var.enable_incident_response ? 1 : 0
  name  = "ir-isolation-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Isolation Lambda: attaches the quarantine SG to a flagged instance (scaffold).
resource "aws_lambda_function" "isolate" {
  count            = var.enable_incident_response ? 1 : 0
  function_name    = "ir-isolate"
  role             = aws_iam_role.isolation_lambda[0].arn
  runtime          = "python3.12"
  handler          = "isolate.handler"
  filename         = data.archive_file.isolate[0].output_path
  source_code_hash = data.archive_file.isolate[0].output_base64sha256
}

# EventBridge rule matching high-severity (>= 7) GuardDuty findings.
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  count = var.enable_incident_response ? 1 : 0
  name  = "ir-guardduty-high-severity"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail      = { severity = [{ numeric = [">=", 7] }] }
  })
}

# Route matching findings to the isolation Lambda.
resource "aws_cloudwatch_event_target" "isolate" {
  count     = var.enable_incident_response ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_high[0].name
  target_id = "ir-isolate"
  arn       = aws_lambda_function.isolate[0].arn
}

# Intra-org forensics role: lets the forensics account assume in to share/copy
# EBS snapshots. Trust is doubly scoped — the forensics account principal AND
# the org id — so no principal outside the organization can assume it.
resource "aws_iam_role" "forensics_snapshot" {
  count = var.enable_incident_response ? 1 : 0
  name  = "ir-forensics-snapshot-share"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.forensics_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:PrincipalOrgID" = var.org_id } }
    }]
  })
}
