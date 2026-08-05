output "external_analyzer_arn" {
  description = "The ARN of the organization external-access analyzer."
  value       = aws_accessanalyzer_analyzer.external.arn
}

output "unused_analyzer_arn" {
  description = "The ARN of the organization unused-access analyzer."
  value       = aws_accessanalyzer_analyzer.unused.arn
}
