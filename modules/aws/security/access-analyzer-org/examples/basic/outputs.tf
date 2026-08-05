output "external_analyzer_arn" {
  description = "The ARN of the organization external-access analyzer created by the module."
  value       = module.access_analyzer_org.external_analyzer_arn
}

output "unused_analyzer_arn" {
  description = "The ARN of the organization unused-access analyzer created by the module."
  value       = module.access_analyzer_org.unused_analyzer_arn
}
