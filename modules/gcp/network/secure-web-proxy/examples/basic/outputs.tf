output "service_attachment_id" {
  description = "Target of the spoke PSC endpoints."
  value       = module.secure_web_proxy.service_attachment_id
}
