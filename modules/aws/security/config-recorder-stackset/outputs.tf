output "stack_set_name" {
  description = "Name of the recorder StackSet."
  value       = aws_cloudformation_stack_set.this.name
}

output "stack_set_id" {
  description = "ID of the recorder StackSet."
  value       = aws_cloudformation_stack_set.this.stack_set_id
}

output "stack_set_instances" {
  description = "Per-Region stack instance deployment targets: target OUs, the account filter and the excluded account."
  value = {
    for r, i in aws_cloudformation_stack_set_instance.this : r => {
      organizational_unit_ids = i.deployment_targets[0].organizational_unit_ids
      account_filter_type     = i.deployment_targets[0].account_filter_type
      accounts                = i.deployment_targets[0].accounts
    }
  }
}

output "failure_tolerance_percentage" {
  description = "The failure tolerance the stack instance operations run with (0 routine, 100 during the migration pass)."
  value       = var.migration_failure_tolerance_percentage
}
