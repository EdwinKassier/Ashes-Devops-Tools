output "sink_writer_identity" {
  description = "Service account identity of the log sink — grant it Storage Object Creator on the destination bucket"
  value       = module.flow_log_export.writer_identity
}
