# Example: add specific engineers to the GCP platform team group.
# Typically used alongside modules/iam/identity_group to populate newly created groups.

module "platform_team_members" {
  source = "../../"

  members = [
    {
      group_id  = "gcp-platform-team@example.com"
      member_id = "alice@example.com"
      roles     = ["MEMBER", "MANAGER"]
    },
    {
      group_id  = "gcp-platform-team@example.com"
      member_id = "bob@example.com"
      roles     = ["MEMBER"]
    },
    {
      group_id  = "gcp-dev-team@example.com"
      member_id = "alice@example.com"
      roles     = ["OWNER"]
    },
  ]
}

output "memberships" {
  description = "Created group membership resources"
  value       = module.platform_team_members.memberships
}
