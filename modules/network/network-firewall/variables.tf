variable "project_id" {
  description = "The ID of the project where the firewall rule will be created"
  type        = string
}

variable "firewall_rule_name" {
  description = "Name of the firewall rule"
  type        = string
}

variable "network" {
  description = "The name or self_link of the network to attach the firewall rule to"
  type        = string
}

variable "direction" {
  description = "Direction of the firewall rule (INGRESS or EGRESS)"
  type        = string
  default     = "INGRESS"
  validation {
    condition     = contains(["INGRESS", "EGRESS"], var.direction)
    error_message = "Direction must be either 'INGRESS' or 'EGRESS'."
  }
}

variable "description" {
  description = "Description of the firewall rule"
  type        = string
  default     = null
}

variable "priority" {
  description = "Priority of the firewall rule (default: 1000)"
  type        = number
  default     = 1000
}

variable "allow_rules" {
  description = "List of allow rules with protocol and ports"
  type = list(object({
    protocol = string
    ports    = optional(list(string))
  }))
  default = []
}

variable "deny_rules" {
  description = "List of deny rules with protocol and ports"
  type = list(object({
    protocol = string
    ports    = optional(list(string))
  }))
  default = []
}

variable "source_ranges" {
  description = "List of source IP CIDR ranges"
  type        = list(string)
  default     = null
}

variable "target_tags" {
  description = "List of target tags for the firewall rule"
  type        = list(string)
  default     = null
}

variable "source_tags" {
  description = "List of source tags for the firewall rule"
  type        = list(string)
  default     = null
}

variable "disabled" {
  description = "Denotes whether the firewall rule is disabled"
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Whether to enable logging for the firewall rule"
  type        = bool
  default     = false
}

variable "log_metadata" {
  description = "Logging metadata configuration (INCLUDE_ALL_METADATA or EXCLUDE_ALL_METADATA)"
  type        = string
  default     = "INCLUDE_ALL_METADATA"
} 