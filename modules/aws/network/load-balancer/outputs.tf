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

output "target_group_arn_suffixes" {
  description = "Map of target group key to its ARN suffix, for CloudWatch TargetGroup metric dimensions."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn_suffix }
}

output "listener_arns" {
  description = "Map of listener key to listener ARN."
  value       = { for k, l in aws_lb_listener.this : k => l.arn }
}

output "listener_rule_arns" {
  description = "Map of listener_rules key to listener rule ARN."
  value       = { for k, r in aws_lb_listener_rule.this : k => r.arn }
}

output "internal" {
  description = "Whether the load balancer is internal (no public IPs)."
  value       = aws_lb.this.internal
}
