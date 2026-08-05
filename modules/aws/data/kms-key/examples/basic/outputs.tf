output "key_arn" {
  description = "The ARN of the CMK created by the module."
  value       = module.kms_key.key_arn
}

output "alias_arn" {
  description = "The ARN of the CMK alias."
  value       = module.kms_key.alias_arn
}
