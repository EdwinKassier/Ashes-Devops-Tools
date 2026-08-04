variable "members" {
  description = "List of members to add to identity groups"
  type = list(object({
    group_id  = string       # The ID of the group to add the member to
    member_id = string       # The ID of the member (e.g., user@domain.com)
    roles     = list(string) # List of roles to assign (e.g., ["MEMBER", "MANAGER"])
  }))
  default = []

  validation {
    condition = alltrue([
      for member in var.members : alltrue([
        for role in member.roles : contains(["MEMBER", "MANAGER", "OWNER"], role)
      ])
    ])
    error_message = "Each role must be one of: MEMBER, MANAGER, OWNER."
  }
}
