# Member-account vending for the SRA landing zone.
#
# Creates a single AWS Organizations member account under a given OU and, when
# requested, its alternate contacts (SECURITY / BILLING / OPERATIONS). The
# organization-managed cross-account access role name is set at creation but its
# lifecycle ignores changes: role_name is not readable after account creation,
# so tracking it would produce a perpetual diff.

resource "aws_organizations_account" "this" {
  name              = var.account_name
  email             = var.email
  parent_id         = var.parent_ou_id
  role_name         = var.cross_account_role_name
  close_on_deletion = var.close_on_deletion
  tags              = merge({ "managed-by" = "terraform" }, var.tags)

  lifecycle {
    ignore_changes = [role_name] # role_name is not readable post-create -> avoids perpetual diff
  }
}

resource "aws_account_alternate_contact" "this" {
  for_each = var.alternate_contacts

  account_id             = aws_organizations_account.this.id
  alternate_contact_type = each.value.contact_type # SECURITY | BILLING | OPERATIONS
  name                   = each.value.name
  title                  = each.value.title
  email_address          = each.value.email_address # NOTE: email_address, NOT email
  phone_number           = each.value.phone_number  # NOTE: phone_number, NOT phone
}
