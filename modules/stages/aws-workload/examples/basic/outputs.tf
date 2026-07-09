output "vpc_id" {
  description = "The ID of the workload spoke VPC."
  value       = module.aws_workload.vpc_id
}

output "tgw_attachment_id" {
  description = "The ID of the spoke VPC's transit-gateway attachment."
  value       = module.aws_workload.tgw_attachment_id
}
