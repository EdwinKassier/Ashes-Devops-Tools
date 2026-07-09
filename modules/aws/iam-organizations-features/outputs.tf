output "enabled_features" {
  description = "The IAM organization features enabled for centralized root access management."
  value       = aws_iam_organizations_features.this.enabled_features
}
