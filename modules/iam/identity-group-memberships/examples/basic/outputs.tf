output "membership_ids" {
  description = "Map of member email to membership resource ID."
  value       = module.platform_team_members.membership_ids
}

output "membership_names" {
  description = "Map of member email to membership resource name."
  value       = module.platform_team_members.membership_names
}
