# Example: add specific engineers to the GCP platform team groups.
# Typically used alongside modules/gcp/iam/identity-group to populate newly
# created groups. group_id is the group's resource name (groups/<id>, the
# identity-group group_names output), not its email address. Every membership
# includes MEMBER; MANAGER and OWNER are added on top of it.

locals {
  platform_team_group = "groups/01abcdefgh234567"
  dev_team_group      = "groups/01ijklmnop890123"
}

module "platform_team_members" {
  source = "../../"

  members = [
    {
      group_id  = local.platform_team_group
      member_id = "alice@example.com"
      roles     = ["MEMBER", "MANAGER"]
    },
    {
      group_id  = local.platform_team_group
      member_id = "bob@example.com"
      roles     = ["MEMBER"]
    },
    {
      group_id  = local.dev_team_group
      member_id = "alice@example.com"
      roles     = ["MEMBER", "OWNER"]
    },
  ]
}
