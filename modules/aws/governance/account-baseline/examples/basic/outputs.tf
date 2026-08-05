output "ebs_encryption_regions" {
  description = "Regions in which default EBS encryption is enforced."
  value       = module.account_baseline.ebs_encryption_regions
}
