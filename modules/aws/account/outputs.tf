output "account_id" {
  description = "The ID of the member account."
  value       = aws_organizations_account.this.id
}

output "account_arn" {
  description = "The ARN of the member account."
  value       = aws_organizations_account.this.arn
}

output "cross_account_role_arn" {
  description = "ARN of the cross-account access role created in the member account."
  value       = "arn:aws:iam::${aws_organizations_account.this.id}:role/${var.cross_account_role_name}"
}
