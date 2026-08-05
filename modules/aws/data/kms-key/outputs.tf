output "key_id" {
  description = "The globally unique identifier (key ID) of the CMK."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "The ARN of the CMK."
  value       = aws_kms_key.this.arn
}

output "alias_arn" {
  description = "The ARN of the CMK alias."
  value       = aws_kms_alias.this.arn
}
