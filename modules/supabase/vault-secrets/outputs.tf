output "managed_secret_names" {
  description = "Sorted list of secret names managed by this module. Visible in plan output — useful for verifying the desired-state map without exposing values."
  value       = sort(nonsensitive(keys(var.secrets)))
}

output "bootstrap_trigger_id" {
  description = "Unique ID of the bootstrap null_resource; changes when the bootstrap script is re-run."
  value       = null_resource.bootstrap.id
}

output "reconcile_trigger_id" {
  description = "Unique ID of the reconcile null_resource; changes when secrets are reconciled."
  value       = null_resource.reconcile.id
}
