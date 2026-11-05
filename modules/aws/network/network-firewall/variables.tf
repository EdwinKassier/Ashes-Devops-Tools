variable "enable_network_firewall" {
  description = "Whether to deploy the Network Firewall. COST TOGGLE: an AWS Network Firewall bills per endpoint-hour (one endpoint per firewall subnet) plus per-GB processed. Set false to remove all firewall resources."
  type        = bool
  default     = true
}

variable "rule_group_capacity" {
  description = "Reserved capacity units for the custom Suricata rule group (only created when suricata_rules is set). Must be sized for the expected number of rules and cannot be changed after creation."
  type        = number
  default     = 100

  validation {
    condition     = var.rule_group_capacity >= 1
    error_message = "rule_group_capacity must be at least 1."
  }
}

variable "rule_group_name" {
  description = "Name of the custom Suricata rule group (the allowlist group is named <rule_group_name>-egress-allowlist)."
  type        = string
  default     = "org-stateful"

  validation {
    condition     = length(trimspace(var.rule_group_name)) > 0
    error_message = "rule_group_name must be a non-empty string."
  }
}

variable "suricata_rules" {
  description = "Optional custom Suricata rules (evaluated at priority 1000, after the AWS-managed threat groups, under STRICT_ORDER). Empty (default) = no custom rule group. Rules must not rely on action-order semantics."
  type        = string
  default     = ""
}

variable "managed_rule_groups" {
  description = "AWS-managed stateful rule group NAMES attached in order (priority 100, 101, ...) as arn:aws:network-firewall:<region>:aws-managed:stateful-rulegroup/<name>. Must be the StrictOrder variants. Defaults: active threat defense (AttackInfrastructure) plus the malware and botnet C2 domain lists. Other examples: ThreatSignaturesMalwareStrictOrder, ThreatSignaturesBotnetStrictOrder, AbusedLegitMalwareDomainsStrictOrder. Managed groups consume policy capacity; active threat defense may carry additional charges."
  type        = list(string)
  default = [
    "AttackInfrastructureStrictOrder",
    "MalwareDomainsStrictOrder",
    "BotNetCommandAndControlDomainsStrictOrder",
  ]

  validation {
    condition     = alltrue([for n in var.managed_rule_groups : can(regex("^[A-Za-z0-9]+StrictOrder$", n))])
    error_message = "managed_rule_groups entries must be AWS-managed rule group names ending in StrictOrder (the policy uses STRICT_ORDER evaluation)."
  }

  validation {
    condition     = length(distinct(var.managed_rule_groups)) == length(var.managed_rule_groups) && length(var.managed_rule_groups) <= 20
    error_message = "managed_rule_groups must be unique and contain at most 20 entries."
  }
}

variable "stateful_default_actions" {
  description = "STRICT_ORDER default actions for traffic no rule matched. Default [\"aws:alert_established\"] = log-but-pass (safe on day one: never blackholes existing flows). AWS-recommended steady state once allow rules exist: [\"aws:drop_established\", \"aws:alert_established\"]. At most one drop and one alert action."
  type        = list(string)
  default     = ["aws:alert_established"]

  validation {
    condition = alltrue([for a in var.stateful_default_actions : contains([
      "aws:drop_strict", "aws:drop_established", "aws:alert_strict", "aws:alert_established",
    ], a)])
    error_message = "stateful_default_actions entries must be aws:drop_strict, aws:drop_established, aws:alert_strict or aws:alert_established."
  }

  validation {
    condition = (
      length([for a in var.stateful_default_actions : a if startswith(a, "aws:drop_")]) <= 1 &&
      length([for a in var.stateful_default_actions : a if startswith(a, "aws:alert_")]) <= 1
    )
    error_message = "stateful_default_actions may contain at most one drop action and one alert action."
  }
}

variable "egress_domain_allowlist" {
  description = "Optional egress domain allowlist matched on HTTP Host and TLS SNI (e.g. [\".amazonaws.com\", \"github.com\"]; a leading dot matches subdomains). When non-empty an ALLOWLIST rule group passes these domains and DROPS all other HTTP/TLS traffic from HOME_NET — set home_net_cidrs to the spoke CIDRs first. Empty (default) = no domain filtering."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.egress_domain_allowlist : can(regex("^[.]?[A-Za-z0-9*]([A-Za-z0-9.*-]{0,251}[A-Za-z0-9])?$", d))])
    error_message = "egress_domain_allowlist entries must be domain names, optionally starting with '.' to match subdomains."
  }
}

variable "domain_allowlist_capacity" {
  description = "Reserved capacity for the egress domain allowlist rule group (roughly 2 x number of domains for HTTP_HOST + TLS_SNI). Cannot be changed after creation."
  type        = number
  default     = 200

  validation {
    condition     = var.domain_allowlist_capacity >= 1
    error_message = "domain_allowlist_capacity must be at least 1."
  }
}

variable "home_net_cidrs" {
  description = "CIDRs set as the policy-level HOME_NET variable. In a centralized inspection VPC this MUST cover the spoke VPCs (e.g. the org supernet); empty (default) = AWS default (the inspection VPC CIDR only)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.home_net_cidrs : can(cidrhost(c, 0))])
    error_message = "home_net_cidrs entries must be valid CIDR blocks."
  }
}

variable "log_prefix" {
  description = "S3 key prefix for the firewall logs in log_bucket_name (ALERT logs under <prefix>/alert, FLOW logs under <prefix>/flow)."
  type        = string
  default     = "network-firewall"

  validation {
    condition     = can(regex("^[A-Za-z0-9!_.*'()/-]{1,200}$", var.log_prefix)) && !startswith(var.log_prefix, "/") && !endswith(var.log_prefix, "/")
    error_message = "log_prefix must be a non-empty S3 key prefix without a leading or trailing '/'."
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

variable "region" {
  description = "Region the firewall is deployed in, used to build the AWS-managed rule group ARNs. Null (default) = the provider's region."
  type        = string
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be null or an AWS region name such as eu-west-2."
  }
}

variable "partition" {
  description = "AWS partition used to build the AWS-managed rule group ARNs."
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "aws-us-gov", "aws-cn"], var.partition)
    error_message = "partition must be one of aws, aws-us-gov, aws-cn."
  }
}
