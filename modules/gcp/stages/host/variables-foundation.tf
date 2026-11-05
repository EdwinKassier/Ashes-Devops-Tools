# Host stage (network foundation) inputs. Part of modules/gcp/stages/host.

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

variable "enable_networking" {
  description = "Enable VPC and network infrastructure provisioning"
  type        = bool
  default     = true
}

variable "enable_cloud_nat" {
  description = "Create Cloud NAT and its Cloud Router for egress. Default true preserves existing behaviour. Set false for VPCs with no egress need (e.g. a DNS-anchor VPC) to avoid the NAT gateway cost."
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "main-vpc"
}

variable "existing_network_id" {
  description = "ID of existing network (when enable_networking is false)"
  type        = string
  default     = ""
}

variable "existing_network_self_link" {
  description = "Self link of existing network (when enable_networking is false)"
  type        = string
  default     = ""
}

variable "database_ports" {
  description = "Database ports to allow from compute to database tier"
  type        = list(string)
  default     = ["3306", "5432", "6379"]
}

variable "enable_iap_access" {
  description = "Enable IAP SSH/RDP access"
  type        = bool
  default     = true
}

variable "enable_private_service_access" {
  description = "Enable Private Service Access for Cloud SQL, Redis, etc."
  type        = bool
  default     = true
}

variable "psa_name" {
  description = "Name of the Private Service Access allocation"
  type        = string
  default     = "google-managed-services"
}

variable "enable_private_service_connect" {
  description = "Enable Private Service Connect for Google APIs"
  type        = bool
  default     = true
}

variable "psa_prefix_length" {
  description = "Prefix length for Private Service Access (e.g. 16 for /16). Valid range: 16–29."
  type        = number
  default     = 16
  validation {
    condition     = var.psa_prefix_length >= 16 && var.psa_prefix_length <= 29
    error_message = "psa_prefix_length must be between 16 and 29 inclusive."
  }
}

variable "psc_target" {
  description = "Target for Private Service Connect (e.g. 'all-apis' or 'vpc-sc')"
  type        = string
  default     = "all-apis"
}

variable "enable_shared_vpc_host" {
  description = "Enable this project as a Shared VPC Host"
  type        = bool
  default     = false
}

variable "enable_firewall_logging" {
  description = "Enable logging for all firewall rules"
  type        = bool
  default     = true
}

variable "compute_tier_ports" {
  description = "Ports allowed from public to compute tier. WARNING: Exposing ports directly to 0.0.0.0/0 is discouraged. Prefer using Global Load Balancers with Cloud Armor."
  type        = list(string)
  default     = ["8080", "8443", "3000"]
}

variable "enable_deletion_protection" {
  description = <<-EOT
    When true, creates a terraform_data guard resource with prevent_destroy = true
    that blocks any plan that would destroy the VPC/subnet stack.

    NOTE: Terraform's prevent_destroy cannot be set from a variable (it must be a
    static literal). The guard resource works around this by existing only when
    protection is enabled — removing it from the plan (e.g. by setting this to
    false) triggers the prevent_destroy error. To intentionally deprovision a
    protected stack, first run:
      terraform state rm '<module_address>.terraform_data.deletion_protection_guard[0]'
  EOT
  type        = bool
  default     = false
}

variable "log_config_aggregation_interval" {
  description = "Flow logs aggregation interval"
  type        = string
  default     = "INTERVAL_5_SEC"
}

variable "log_config_flow_sampling" {
  description = "Flow logs sampling rate (0.0 to 1.0). 0.0 disables sampling; 1.0 captures all flows."
  type        = number
  default     = 0.5
  validation {
    condition     = var.log_config_flow_sampling >= 0.0 && var.log_config_flow_sampling <= 1.0
    error_message = "log_config_flow_sampling must be between 0.0 and 1.0 inclusive."
  }
}

variable "subnet_cidrs" {
  description = "Subnet CIDRs for public, private, and database tiers"
  type = object({
    public   = list(string)
    private  = list(string)
    database = list(string)
  })
  default = {
    public   = []
    private  = []
    database = []
  }
}

variable "secondary_ranges" {
  description = "Secondary IP ranges for private subnets (required for GKE Pods/Services). Key is the zone name."
  type = map(list(object({
    range_name    = string
    ip_cidr_range = string
  })))
  default = {}
}

# =============================================================================
# INTEGRATED NAT CONFIGURATION
# =============================================================================

variable "integrated_nat_ip_allocate_option" {
  description = "IP allocation mode for the integrated NAT gateway. AUTO_ONLY uses Google-managed IPs; MANUAL_ONLY uses reserved static IPs (also configure nat_ips in standalone_nat_gateways)."
  type        = string
  default     = "AUTO_ONLY"
  validation {
    condition     = contains(["AUTO_ONLY", "MANUAL_ONLY"], var.integrated_nat_ip_allocate_option)
    error_message = "integrated_nat_ip_allocate_option must be AUTO_ONLY or MANUAL_ONLY."
  }
}

variable "integrated_nat_log_filter" {
  description = "Log filter for the integrated NAT gateway. ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  type        = string
  default     = "ERRORS_ONLY"
  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.integrated_nat_log_filter)
    error_message = "integrated_nat_log_filter must be ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  }
}

