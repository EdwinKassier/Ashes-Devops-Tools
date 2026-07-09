output "organization_id" {
  description = "The ID of the AWS organization."
  value       = aws_organizations_organization.this.id
}

output "organization_arn" {
  description = "The ARN of the AWS organization."
  value       = aws_organizations_organization.this.arn
}

output "roots_id" {
  description = "The ID of the organization root, under which the top-level OUs are created."
  value       = aws_organizations_organization.this.roots[0].id
}

output "ou_ids" {
  description = "Map of OU name to OU ID. Top-level OUs are keyed by name; child OUs are keyed by their full \"parent/name\" path."
  value = merge(
    { for name, ou in aws_organizations_organizational_unit.top : name => ou.id },
    { for key, ou in aws_organizations_organizational_unit.child : key => ou.id },
  )
}

output "management_account_id" {
  description = "The account ID of the organization management (master) account."
  value       = aws_organizations_organization.this.master_account_id
}
