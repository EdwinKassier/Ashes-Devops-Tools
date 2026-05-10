output "groups" {
  description = "Created identity groups keyed by group email"
  value       = module.gcp_groups.identity_groups
}
