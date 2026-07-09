output "detector_ids" {
  description = "Map of Region to the GuardDuty detector ID created in that Region."
  value       = module.guardduty_org.detector_ids
}
