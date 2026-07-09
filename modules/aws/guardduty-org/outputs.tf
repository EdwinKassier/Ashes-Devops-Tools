output "detector_ids" {
  description = "Map of Region to the GuardDuty detector ID created in that Region."
  value       = { for region, d in aws_guardduty_detector.this : region => d.id }
}
