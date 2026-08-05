output "account_id" {
  description = "The ID of the member account created by the module."
  value       = module.account.account_id
}

output "cross_account_role_arn" {
  description = "ARN of the cross-account access role in the member account."
  value       = module.account.cross_account_role_arn
}
