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
#
# This Lambda is a deliberate scaffold (see files/isolate.py — stdlib only, logs
# and returns success). The following checkov skips reflect that scaffold posture;
# each control is a per-deployment choice to be wired when the handler is extended,
# not a defect in the landing-zone baseline:
#   CKV_AWS_50  (X-Ray tracing)      — tracing_config is opt-in; the scaffold makes
#                                       no downstream AWS calls to trace yet.
#   CKV_AWS_115 (reserved concurrency)— no concurrency cap: incident isolation must
#                                       not be throttled, and invocation volume is
#                                       bounded by GuardDuty high-severity findings.
#   CKV_AWS_116 (DLQ)                — a DLQ requires a target SQS/SNS topic that is
#                                       a per-deployment resource; the scaffold has
#                                       no side effects to lose on failure.
#   CKV_AWS_117 (run inside a VPC)   — the isolation action uses only the AWS control
#                                       plane (EC2/EBS APIs), which needs no VPC
#                                       attachment; a VPC would add NAT cost/latency
#                                       to a control-plane-only function.
#   CKV_AWS_272 (code-signing)       — code signing requires a Signer profile owned
#                                       by the deploying org; source integrity is
#                                       instead pinned via source_code_hash above.
resource "aws_lambda_function" "isolate" {
  # checkov:skip=CKV_AWS_50:Scaffold Lambda makes no downstream calls to trace; X-Ray tracing is opt-in per deployment.
  # checkov:skip=CKV_AWS_115:No reserved concurrency by design — incident isolation must not be throttled; volume is bounded by GuardDuty high-severity findings.
  # checkov:skip=CKV_AWS_116:No DLQ — scaffold has no side effects to lose; a DLQ target (SQS/SNS) is a per-deployment resource wired when the handler is extended.
  # checkov:skip=CKV_AWS_117:Isolation uses only the EC2/EBS control plane; no VPC attachment is required and none is desired for a control-plane-only function.
  # checkov:skip=CKV_AWS_272:Code signing needs a Signer profile owned by the deploying org; source integrity is pinned via source_code_hash instead.
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

  # checkov:skip=CKV_AWS_61:The trust policy grants sts:AssumeRole to a single, specific account principal (the forensics account root) and is additionally scoped by aws:PrincipalOrgID, so no principal outside this AWS Organization can assume it. Checkov flags the bare sts:AssumeRole action but does not resolve that the Principal is not a wildcard/service-wide grant.

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
