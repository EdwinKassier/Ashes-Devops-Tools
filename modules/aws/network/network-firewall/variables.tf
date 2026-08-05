variable "enable_network_firewall" {
  description = "Whether to deploy the Network Firewall. COST TOGGLE: an AWS Network Firewall bills per endpoint-hour (one endpoint per firewall subnet) plus per-GB processed. Set false to remove all firewall resources."
  type        = bool
  default     = true
}

variable "rule_group_capacity" {
  description = "Reserved capacity units for the stateful rule group. Must be sized for the expected number of rules and cannot be changed after creation."
  type        = number
  default     = 100

  validation {
    condition     = var.rule_group_capacity >= 1
    error_message = "rule_group_capacity must be at least 1."
  }
}

variable "rule_group_name" {
  description = "Name of the stateful rule group."
  type        = string
  default     = "org-stateful"

  validation {
    condition     = length(trimspace(var.rule_group_name)) > 0
    error_message = "rule_group_name must be a non-empty string."
  }
}

variable "suricata_rules" {
  description = "Suricata rules string for the stateful rule group. Defaults to a minimal drop rule; replace with the org rule set or AWS-managed rule references in production."
  type        = string
  default     = "drop http any any -> any any (msg:\"deny by default\"; sid:1; rev:1;)"

  validation {
    condition     = length(trimspace(var.suricata_rules)) > 0
    error_message = "suricata_rules must be a non-empty Suricata rules string."
  }
}

variable "policy_name" {
  description = "Name of the firewall policy."
  type        = string
  default     = "org-fw-policy"

  validation {
    condition     = length(trimspace(var.policy_name)) > 0
    error_message = "policy_name must be a non-empty string."
  }
}

variable "firewall_name" {
  description = "Name of the firewall."
  type        = string
  default     = "org-firewall"

  validation {
    condition     = length(trimspace(var.firewall_name)) > 0
    error_message = "firewall_name must be a non-empty string."
  }
}

variable "inspection_vpc_id" {
  description = "ID of the inspection VPC the firewall is deployed into."
  type        = string

  validation {
    condition     = length(trimspace(var.inspection_vpc_id)) > 0
    error_message = "inspection_vpc_id must be a non-empty string."
  }
}

variable "firewall_subnet_ids" {
  description = "Subnet IDs (one per AZ, in the inspection VPC) the firewall creates endpoints in. One subnet_mapping is created per ID."
  type        = list(string)
  default     = ["subnet-aaaa", "subnet-bbbb"]

  validation {
    condition     = length(var.firewall_subnet_ids) > 0
    error_message = "firewall_subnet_ids must contain at least one subnet."
  }
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket that receives firewall flow logs."
  type        = string

  validation {
    condition     = length(trimspace(var.log_bucket_name)) > 0
    error_message = "log_bucket_name must be a non-empty string."
  }
}

variable "kms_key_arn" {
  description = "ARN of a customer-managed KMS key used to encrypt the rule group, policy, and firewall at rest (CUSTOMER_KMS). Empty string falls back to AWS-owned keys; the network-hub stage that owns the KMS key wires this in production."
  type        = string
  default     = ""
}

variable "delete_protection" {
  description = "Whether to enable deletion protection on the firewall. On by default so the inspection firewall is not torn down accidentally; set false to allow teardown."
  type        = bool
  default     = true
}
