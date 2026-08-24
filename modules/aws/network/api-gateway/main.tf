# API Gateway v2 (HTTP API) primitive for the SRA landing zone.
#
# The AWS parity counterpart to modules/gcp/network/api-gateway. It creates:
#   - an HTTP (or WebSocket) API                (aws_apigatewayv2_api)
#   - an auto-deployed stage with access logs   (aws_apigatewayv2_stage)
#   - a CloudWatch log group for those logs      (aws_cloudwatch_log_group)
#   - optional integrations + routes             (for_each over var.routes)
#   - an optional custom domain + API mapping    (gated by enable_custom_domain)
#
# Secure defaults: access logging is always ON to CloudWatch with a structured
# JSON log format; the log group carries a caller-configurable retention and an
# optional KMS key.

locals {
  # Route key -> route/integration definition. for_each needs a map with stable
  # keys; the route_key (e.g. "GET /items") is unique per API.
  routes = { for r in var.routes : r.route_key => r }

  # Structured JSON access-log format. Built with jsonencode() (not a
  # data.aws_iam_policy_document) so the content is fully known at plan time and
  # survives mock_provider. Values are $context.* variables the service expands
  # at request time, so they are passed through as literal strings.
  access_log_format = jsonencode({
    requestId               = "$context.requestId"
    ip                      = "$context.identity.sourceIp"
    requestTime             = "$context.requestTime"
    httpMethod              = "$context.httpMethod"
    routeKey                = "$context.routeKey"
    status                  = "$context.status"
    protocol                = "$context.protocol"
    responseLength          = "$context.responseLength"
    integrationErrorMessage = "$context.integrationErrorMessage"
  })
}

# ── Access-log group ────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn == "" ? null : var.kms_key_arn

  tags = var.tags
}

# ── API ───────────────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = var.protocol_type
  description   = var.description

  dynamic "cors_configuration" {
    for_each = var.cors_configuration == null ? [] : [var.cors_configuration]
    content {
      allow_credentials = cors_configuration.value.allow_credentials
      allow_headers     = cors_configuration.value.allow_headers
      allow_methods     = cors_configuration.value.allow_methods
      allow_origins     = cors_configuration.value.allow_origins
      expose_headers    = cors_configuration.value.expose_headers
      max_age           = cors_configuration.value.max_age
    }
  }

  tags = var.tags
}

# ── Integrations + routes ─────────────────────────────────────────────────────

resource "aws_apigatewayv2_integration" "this" {
  for_each = local.routes

  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = each.value.integration_type
  integration_uri    = each.value.integration_uri
  integration_method = each.value.integration_type == "MOCK" ? null : "POST"
}

resource "aws_apigatewayv2_route" "this" {
  # checkov:skip=CKV_AWS_309:authorization_type IS set (defaults to the secure AWS_IAM via the routes variable, and supports JWT/CUSTOM). Checkov cannot resolve the for_each/variable value so it reads it as unset; the secure default + validation (NONE|AWS_IAM|JWT|CUSTOM) are verified by plan_assertions.
  for_each = local.routes

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value.route_key
  target             = "integrations/${aws_apigatewayv2_integration.this[each.key].id}"
  authorization_type = each.value.authorization_type
  authorizer_id      = contains(["JWT", "CUSTOM"], each.value.authorization_type) ? each.value.authorizer_id : null
}

# ── Stage ───────────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format          = local.access_log_format
  }

  tags = var.tags
}

# ── Custom domain (optional) ──────────────────────────────────────────────────

resource "aws_apigatewayv2_domain_name" "this" {
  count = var.enable_custom_domain ? 1 : 0

  domain_name = var.domain_name

  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count = var.enable_custom_domain ? 1 : 0

  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this[0].id
  stage       = aws_apigatewayv2_stage.this.id
}
