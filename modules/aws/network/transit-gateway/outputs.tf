output "tgw_id" {
  description = "The ID of the transit gateway."
  value       = aws_ec2_transit_gateway.this.id
}

output "route_table_ids" {
  description = "Map of segment name to transit gateway route table ID."
  value       = { for name, rt in aws_ec2_transit_gateway_route_table.this : name => rt.id }
}

output "attachment_ids" {
  description = "Map of attachment name to transit gateway VPC attachment ID."
  value       = { for name, att in aws_ec2_transit_gateway_vpc_attachment.this : name => att.id }
}
