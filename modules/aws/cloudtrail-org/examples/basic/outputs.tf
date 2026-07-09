output "trail_arn" {
  description = "The ARN of the organization CloudTrail trail created by the module."
  value       = module.cloudtrail_org.trail_arn
}

output "trail_name" {
  description = "The name of the organization CloudTrail trail."
  value       = module.cloudtrail_org.trail_name
}
