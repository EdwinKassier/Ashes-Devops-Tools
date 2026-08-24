output "arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "arn_suffix" {
  description = "ARN suffix of the load balancer, for use in CloudWatch metric dimensions."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "DNS name of the load balancer."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Route 53 hosted zone ID of the load balancer, for alias records."
  value       = aws_lb.this.zone_id
}

output "target_group_arns" {
  description = "Map of target group key to the created target group ARN."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}

output "security_group_id" {
  description = "ID of the module-created security group, or null when create_security_group = false."
  value       = var.create_security_group ? aws_security_group.this[0].id : null
}
