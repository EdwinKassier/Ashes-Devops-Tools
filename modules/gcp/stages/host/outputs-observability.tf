# Host stage (observability) outputs. Part of modules/gcp/stages/host.

# =============================================================================
# VPC FLOW LOGS EXPORT OUTPUTS
# =============================================================================

output "vpc_flow_logs" {
  description = "The VPC Flow Logs export module outputs (if enabled)"
  value       = var.enable_vpc_flow_logs_export ? module.vpc_flow_logs[0] : null
}

output "vpc_flow_logs_sink_id" {
  description = "The ID of the VPC Flow Logs sink"
  value       = var.enable_vpc_flow_logs_export ? module.vpc_flow_logs[0].id : null
}

output "vpc_flow_logs_writer_identity" {
  description = "The service account identity for the flow logs sink writer"
  value       = var.enable_vpc_flow_logs_export ? module.vpc_flow_logs[0].writer_identity : null
}

# =============================================================================
# PACKET MIRRORING OUTPUTS
# =============================================================================

output "packet_mirroring_policies" {
  description = "All packet mirroring policy outputs"
  value       = module.packet_mirroring
}

output "packet_mirroring_policy_ids" {
  description = "The IDs of all packet mirroring policies"
  value = {
    for k, v in module.packet_mirroring : k => v.id
  }
}

# =============================================================================
# VPC FLOW LOGS OUTPUTS
# =============================================================================

output "vpc_flow_logs_kms_keyring_name" {
  description = "The KMS keyring name created for VPC Flow Logs encryption. Null when enable_vpc_flow_logs_export is false."
  value       = var.enable_vpc_flow_logs_export ? module.flow_logs_kms[0].keyring_name : null
}

output "vpc_flow_logs_kms_key_name" {
  description = "The fully-qualified KMS crypto key name used to encrypt VPC Flow Logs data (BigQuery and GCS). Null when enable_vpc_flow_logs_export is false."
  value       = var.enable_vpc_flow_logs_export ? module.flow_logs_kms[0].key_names["vpc-flow-logs"] : null
}

output "vpc_flow_logs_sink_name" {
  description = "The name of the Cloud Logging sink that exports VPC Flow Logs. Null when enable_vpc_flow_logs_export is false."
  value       = var.enable_vpc_flow_logs_export ? module.vpc_flow_logs[0].name : null
}

output "vpc_flow_logs_sink_writer_identity" {
  description = "The service account identity of the Cloud Logging sink writer. Grant this identity write access to the destination. Null when disabled."
  value       = var.enable_vpc_flow_logs_export ? module.vpc_flow_logs[0].writer_identity : null
}
