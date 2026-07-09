output "trail_arn" {
  description = "The ARN of the organization CloudTrail trail."
  value       = aws_cloudtrail.org.arn
}

output "trail_name" {
  description = "The name of the organization CloudTrail trail."
  value       = aws_cloudtrail.org.name
}
