variable "vpc_id" {
  description = "ID of the central hub VPC that hosts the interface endpoints and the shared private hosted zone."
  type        = string

  validation {
    condition     = length(trimspace(var.vpc_id)) > 0
    error_message = "vpc_id must be a non-empty string."
  }
}

variable "region" {
  description = "AWS region, used to build interface endpoint service names (com.amazonaws.<region>.<service>)."
  type        = string

  validation {
    # Matches AWS region ids like eu-west-2, us-east-1, ap-southeast-3.
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region id (e.g. eu-west-2)."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs (one per AZ, in the hub VPC) to place the interface endpoint ENIs in."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs to associate with the interface endpoint ENIs."
  type        = list(string)
  default     = []
}

variable "interface_services" {
  description = "AWS services to create centralized Interface VPC endpoints for. Service names are built as com.amazonaws.<region>.<service>."
  type        = list(string)
  default     = ["ec2", "ssm", "ssmmessages", "ec2messages", "kms", "logs", "sts"]

  validation {
    condition     = length(var.interface_services) > 0
    error_message = "interface_services must contain at least one service."
  }
}

variable "org_id" {
  description = "AWS Organizations org id (o-xxxxxxxxxx) used in the endpoint policy aws:PrincipalOrgID condition to scope access to this organization."
  type        = string

  validation {
    condition     = length(trimspace(var.org_id)) > 0
    error_message = "org_id must be a non-empty string."
  }
}

variable "private_hosted_zone_name" {
  description = "Name of the shared Route 53 private hosted zone for split-horizon DNS. Empty string skips creating the zone."
  type        = string
  default     = ""
}
