output "api_id" {
  description = "The identifier of the HTTP API."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "The default endpoint (URI) of the API."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_arn" {
  description = "The ARN of the API."
  value       = aws_apigatewayv2_api.this.arn
}

output "stage_arn" {
  description = "The ARN of the stage."
  value       = aws_apigatewayv2_stage.this.arn
}

output "stage_invoke_url" {
  description = "The invoke URL of the stage."
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "log_group_arn" {
  description = "The ARN of the access-log CloudWatch log group."
  value       = aws_cloudwatch_log_group.access.arn
}
