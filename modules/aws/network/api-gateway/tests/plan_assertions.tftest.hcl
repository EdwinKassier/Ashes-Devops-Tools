# Resource-assertion tests for the api-gateway module.
# Asserts on config-derived, plan-knowable attributes only — provider-normalized
# attributes (ids, arns, endpoints) are UNKNOWN under mock_provider.

mock_provider "aws" {}

variables {
  name          = "orders-api"
  protocol_type = "HTTP"
  routes = [
    {
      route_key       = "GET /items"
      integration_uri = "arn:aws:lambda:eu-west-1:123456789012:function:list-items"
    },
  ]
  log_retention_days = 90
}

run "api_and_stage_wiring" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_api.this.protocol_type == "HTTP"
    error_message = "the API must be planned with the supplied protocol_type."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.name == "orders-api"
    error_message = "the API must be planned with the supplied name."
  }

  assert {
    condition     = aws_apigatewayv2_stage.this.auto_deploy == true
    error_message = "the stage must be planned with auto_deploy enabled."
  }

  assert {
    condition     = aws_cloudwatch_log_group.access.retention_in_days == 90
    error_message = "the access-log group must use the supplied retention."
  }

  assert {
    condition     = aws_cloudwatch_log_group.access.name == "/aws/apigateway/orders-api"
    error_message = "the access-log group name must derive from var.name."
  }
}

run "route_planned_when_provided" {
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_route.this) == 1
    error_message = "exactly one route must be planned for the single supplied route."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["GET /items"].route_key == "GET /items"
    error_message = "the route must be planned with the supplied route_key."
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["GET /items"].integration_type == "AWS_PROXY"
    error_message = "the integration must default to AWS_PROXY."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["GET /items"].authorization_type == "AWS_IAM"
    error_message = "routes must default to the secure AWS_IAM authorization type."
  }
}

run "no_routes_by_default" {
  command = plan

  variables {
    routes = []
  }

  assert {
    condition     = length(aws_apigatewayv2_route.this) == 0
    error_message = "no routes must be planned when var.routes is empty."
  }
}

run "custom_domain_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_domain_name.this) == 0
    error_message = "the custom domain must not be created by default."
  }
}
