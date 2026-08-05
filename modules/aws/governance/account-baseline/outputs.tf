output "ebs_encryption_regions" {
  description = "Regions in which default EBS encryption is enforced."
  value       = keys(aws_ebs_encryption_by_default.this)
}
