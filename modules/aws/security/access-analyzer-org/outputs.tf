output "external_analyzer_arn" {
  description = "The ARN of the organization external-access analyzer."
  value       = aws_accessanalyzer_analyzer.external.arn
}

output "unused_analyzer_arn" {
  description = "The ARN of the organization unused-access analyzer."
  value       = aws_accessanalyzer_analyzer.unused.arn
}

output "external_analyzer_arns_by_region" {
  description = "Map of region to external-access analyzer ARN for the extra regions (home region: external_analyzer_arn)."
  value       = { for r, a in aws_accessanalyzer_analyzer.external_extra : r => a.arn }
}

output "internal_analyzer_arn" {
  description = "ARN of the home-region organization internal-access analyzer, or null when disabled."
  value       = one(aws_accessanalyzer_analyzer.internal[*].arn)
}
