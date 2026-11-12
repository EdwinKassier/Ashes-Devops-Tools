# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via the TF_CLOUD_ORGANIZATION environment variable (kept out of the code so the same root works across orgs and CI). Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from."
  type        = string
  default     = "aws-organization"
}

variable "organization_contract" {
  description = "aws-organization stage contract (FAST-style override), the same type in every aws root: organization_id (o-xxxxxxxxxx), organization_root_id (r-xxxx), management_account_id, ou_ids (OU name => OU ID), account_ids (account key => 12-digit ID), account_role_arns (account key => cross-account role ARN). This root needs: organization_id, management_account_id, account_ids. When set, the aws-organization remote state is NOT read. Null = aws.contracts.organization from config/landing-zone.yaml, else the contract output of the organization_workspace_name workspace."
  type = object({
    organization_id       = optional(string)
    organization_root_id  = optional(string)
    management_account_id = optional(string)
    ou_ids                = optional(map(string), {})
    account_ids           = map(string)
    account_role_arns     = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.organization_contract == null || alltrue([for id in values(try(var.organization_contract.account_ids, {})) : can(regex("^[0-9]{12}$", id))])
    error_message = "organization_contract.account_ids values must be 12-digit AWS account IDs."
  }

  validation {
    condition     = var.organization_contract == null || alltrue([for k in ["organization_id", "management_account_id"] : try(length(trimspace(var.organization_contract[k])) > 0, false)])
    error_message = "organization_contract must set organization_id, management_account_id for this root."
  }
}

# -----------------------------------------------------------------------------
# Provider region + IPAM operating regions
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region the network hub is deployed in and the region the default provider assumes the network-account role in. Null = org.regions.aws from config/landing-zone.yaml, else eu-west-2."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")))
    error_message = "aws_region (or org.regions.aws in config/landing-zone.yaml) must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "aws_enabled_regions" {
  description = "Regions IPAM operates in. Each becomes an operating region on the IPAM and gets its own regional pool. Null = aws.enabled_regions from config/landing-zone.yaml, else [\"eu-west-2\"]."
  type        = list(string)
  default     = null

  validation {
    condition     = length(var.aws_enabled_regions != null ? var.aws_enabled_regions : coalesce(local.cfg.aws_enabled_regions, ["eu-west-2"])) > 0
    error_message = "aws_enabled_regions (or aws.enabled_regions in config/landing-zone.yaml) must contain at least one region."
  }
}

# -----------------------------------------------------------------------------
# Addressing plan (IPAM + inspection/egress VPCs)
# -----------------------------------------------------------------------------

variable "top_cidr" {
  description = "CIDR of the top-level supernet owned by the top IPAM pool. Null = aws.network.top_cidr from config/landing-zone.yaml, else 10.64.0.0/10 (the AWS block of docs/architecture/cidr-plan.md)."
  type        = string
  default     = null

  validation {
    condition     = var.top_cidr == null || can(cidrhost(var.top_cidr, 0))
    error_message = "top_cidr must be a valid IPv4 CIDR block (e.g. 10.64.0.0/10)."
  }
}

variable "regional_cidrs" {
  description = "Map of region to the CIDR each regional IPAM pool provisions. Every CIDR should fall within top_cidr. Null = aws.network.regional_cidrs from config/landing-zone.yaml, else { <aws_region, or the first enabled region when aws_region is not enabled> = 10.64.0.0/12 }."
  type        = map(string)
  default     = null

  validation {
    condition     = var.regional_cidrs == null || alltrue([for c in values(coalesce(var.regional_cidrs, {})) : can(cidrhost(c, 0))])
    error_message = "Every value in regional_cidrs must be a valid IPv4 CIDR block."
  }
}

variable "inspection_cidr" {
  description = "IPv4 CIDR of the inspection VPC that hosts the Network Firewall endpoints and its transit-gateway attachment. Null = aws.network.inspection_cidr from config/landing-zone.yaml, else 10.64.0.0/16."
  type        = string
  default     = null

  validation {
    condition     = var.inspection_cidr == null || can(cidrnetmask(var.inspection_cidr))
    error_message = "inspection_cidr must be a valid IPv4 CIDR block (e.g. 10.64.0.0/16)."
  }
}

variable "egress_cidr" {
  description = "IPv4 CIDR of the centralized egress VPC that hosts the NAT gateways, interface endpoints, and Route 53 resolver endpoints. Null = aws.network.egress_cidr from config/landing-zone.yaml, else 10.65.0.0/16."
  type        = string
  default     = null

  validation {
    condition     = var.egress_cidr == null || can(cidrnetmask(var.egress_cidr))
    error_message = "egress_cidr must be a valid IPv4 CIDR block (e.g. 10.65.0.0/16)."
  }
}

variable "availability_zones" {
  description = "Availability zone NAMES for the hub VPCs, valid in this account only (a name can map to a different physical zone in another account). Null (default) resolves them from availability_zone_ids, else aws.network.availability_zone_ids from config/landing-zone.yaml, else the region's first three available zones. Only the first az_count entries are used."
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zones == null ? true : length(var.availability_zones) > 0
    error_message = "availability_zones must contain at least one zone."
  }
}

variable "availability_zone_ids" {
  description = "Availability zone IDs (for example euw2-az2), the same physical zones in every account. Ignored when availability_zones is set. Null = aws.network.availability_zone_ids from config/landing-zone.yaml, else the region's first three available zones. Changing the resolved zone names of an existing estate replaces its subnets: see UPGRADING.md."
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zone_ids == null ? true : length(var.availability_zone_ids) > 0 && alltrue([for id in var.availability_zone_ids : can(regex("^[a-z]+[0-9]+-az[0-9]+$", id))])
    error_message = "availability_zone_ids must be a non-empty list of AZ IDs such as euw2-az2 or use1-az4."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread each subnet tier across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be between 2 and 3 (the Route 53 Resolver endpoints need subnets in at least two AZs)."
  }

  # Resolved zones (IDs or the region) are checked by the
  # aws_availability_zones postcondition in azs.tf.
  validation {
    condition     = var.availability_zones == null ? true : var.az_count <= length(var.availability_zones)
    error_message = "az_count must not exceed the number of availability_zones provided."
  }
}

# -----------------------------------------------------------------------------
# Log-archive naming contract + DNS + toggles
# -----------------------------------------------------------------------------

variable "log_archive_bucket_name" {
  description = "Deterministic name of the central log-archive bucket that receives VPC flow logs and Network Firewall logs. Cross-root naming contract: it MUST match the name the aws-organization and aws-security roots use. Null = aws.log_archive_bucket_name from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(coalesce(var.log_archive_bucket_name, local.cfg.log_archive_bucket_name, " "))) > 0
    error_message = "log_archive_bucket_name is unset: set var.log_archive_bucket_name or aws.log_archive_bucket_name in config/landing-zone.yaml to a non-empty S3 bucket name."
  }
}

variable "private_hosted_zone_name" {
  description = "Name of the shared Route 53 private hosted zone for split-horizon DNS in the egress VPC. Empty string skips creating the zone."
  type        = string
  default     = ""
}

variable "enable_network_firewall" {
  description = "Whether to deploy the Network Firewall in the inspection VPC. COST TOGGLE: bills per endpoint-hour plus per-GB processed. Null (default) follows profile: on for production, off for starter."
  type        = bool
  default     = null
}

variable "enable_network_access_analyzer" {
  description = "Whether to create the Network Access Analyzer scope that flags segmentation-intent violations. Off by default."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Tagging — provider default_tags (FinOps / governance)
#
# Every resource the aws provider(s) in this root create gets the canonical tag
# set: CostCenter / Environment / Owner (the keys the tag policy enforces and
# cost-governance activates as cost-allocation tags) plus ManagedBy /
# LandingZone / Workspace. default_tags is merged LAST, so it can add keys or
# override any canonical value.
# -----------------------------------------------------------------------------

variable "landing_zone_name" {
  description = "Landing-zone identifier written to the LandingZone tag on every resource. Null = org.name from config/landing-zone.yaml (the single source shared by every AWS root). The upstream placeholders \"ashes\" and \"my-org\" are rejected."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "!unset")))
    error_message = "landing_zone_name is unset or invalid: set var.landing_zone_name or org.name in config/landing-zone.yaml. It must be 2-31 chars: a lowercase letter, then lowercase letters, digits or hyphens."
  }

  validation {
    condition     = !contains(["ashes", "my-org"], lower(coalesce(var.landing_zone_name, local.cfg.landing_zone_name, "!unset")))
    error_message = "landing_zone_name is still an upstream placeholder (ashes / my-org). Set your own landing-zone identifier."
  }
}

variable "cost_center" {
  description = "Value of the CostCenter cost-allocation tag on every resource in this root. Null = org.cost_center from config/landing-zone.yaml, else \"platform\"."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(var.cost_center != null ? var.cost_center : coalesce(local.cfg.cost_center, "platform"))) > 0
    error_message = "cost_center must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "owner" {
  description = "Value of the Owner cost-allocation tag on every resource in this root (team or distribution list). Null = org.owner from config/landing-zone.yaml, else \"platform-team\"."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(var.owner != null ? var.owner : coalesce(local.cfg.owner, "platform-team"))) > 0
    error_message = "owner must be a non-empty string (empty tag values cause perpetual diffs)."
  }
}

variable "default_tags" {
  description = "Extra tags merged into the aws provider default_tags (after the canonical set, so they may override it). Values must be non-empty."
  type        = map(string)
  default     = {}

  validation {
    # An empty-string default tag makes the provider plan a perpetual diff.
    condition     = alltrue([for v in values(var.default_tags) : length(trimspace(v)) > 0])
    error_message = "default_tags values must be non-empty strings."
  }
}

# -----------------------------------------------------------------------------
# Credentials
# -----------------------------------------------------------------------------

variable "assume_role_arn" {
  description = "Optional role the aws provider(s) assume. Default null: the workspace's TFC dynamic credentials (TFC_AWS_PROVIDER_AUTH + TFC_AWS_PLAN_ROLE_ARN / TFC_AWS_APPLY_ROLE_ARN, from the aws-organization outputs tfc_plan_role_arns / tfc_apply_role_arns) already resolve to the target member account, so no hop is made. Legacy / local runs from management-account credentials set this to the account's account_role_arns entry (OrganizationAccountAccessRole)."
  type        = string
  default     = null

  validation {
    condition     = var.assume_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.assume_role_arn, "x")))
    error_message = "assume_role_arn must be null or an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

variable "profile" {
  description = "Cost/assurance profile: production (default; full inspection and detection stack) or starter (cheapest safe non-prod baseline). It only changes the defaults of the profile-driven toggles; any explicit toggle still wins. Null = org.profile from config/landing-zone.yaml, else production."
  type        = string
  default     = null

  validation {
    condition     = var.profile == null || contains(["production", "starter"], coalesce(var.profile, "production"))
    error_message = "profile must be production or starter."
  }
}

variable "enforce_egress_allowlist" {
  description = "Fail the plan unless the firewall drops unmatched egress and carries a domain allowlist (or the waiver is set). Null = on when the profile is production and an aws.workload_environments entry is_production (required on every entry; the environment name is not read)."
  type        = bool
  default     = null

  validation {
    condition     = var.enforce_egress_allowlist != null || length(local.cfg.workload_missing_is_production) == 0
    error_message = "Every aws.workload_environments entry in config/landing-zone.yaml must set is_production: true or false; the environment name is not read. Missing or invalid: ${join(", ", local.cfg.workload_missing_is_production)}."
  }
}

variable "network_firewall_egress_domain_allowlist" {
  description = "Egress domain allowlist matched on HTTP Host / TLS SNI; a leading dot matches subdomains. Null = aws.network.egress_domain_allowlist from config, else empty (no domain filtering)."
  type        = list(string)
  default     = null
}

variable "network_firewall_stateful_default_actions" {
  description = "STRICT_ORDER default actions for unmatched traffic. Null = aws.network.stateful_default_actions from config, else [\"aws:alert_established\"] (log-but-pass). Production needs aws:drop_established."
  type        = list(string)
  default     = null
}

variable "egress_alert_only_waived" {
  description = "Explicitly waive the production fail-closed egress gate (alert-only inspection). Null = aws.network.egress_alert_only_waived from config, else false."
  type        = bool
  default     = null
}

variable "enable_vpn" {
  description = "Attach an on-premises Site-to-Site VPN to the transit gateway. Null = aws.network.vpn.enabled from config/landing-zone.yaml, else false. Needs vpn.customer_gateway_ip and the Network Firewall (profile production or enable_network_firewall = true): the plan fails without it."
  type        = bool
  default     = null
}

variable "enable_resolver_endpoints" {
  description = "Create the Route 53 Resolver inbound and outbound endpoints in the egress VPC (about USD 365 per month). Null = aws.network.resolver_endpoints.enabled from config/landing-zone.yaml, else on only when the VPN is on."
  type        = bool
  default     = null
}

variable "vpn" {
  description = "Site-to-Site VPN settings (customer_gateway_ip, customer_gateway_bgp_asn, static_routes_only, onprem_cidrs, tunnel_inside_cidrs, enable_acceleration, preshared_key_storage), used only when the VPN is enabled. Null = aws.network.vpn from config/landing-zone.yaml. The tunnel pre-shared keys are never set here: AWS stores them in Secrets Manager."
  # Untyped so this variable and the config-file value (JSON text) share one
  # decode path, and so a misspelled key stays visible: an object type
  # constraint would drop it silently. The validation rejects unknown keys
  # (config/landing-zone.schema.json does the same for the config file); the
  # network-hub stage types and validates the values.
  type    = any
  default = null

  validation {
    condition     = length([for k in try(keys(var.vpn), []) : k if !contains(["customer_gateway_ip", "customer_gateway_bgp_asn", "static_routes_only", "onprem_cidrs", "tunnel_inside_cidrs", "enable_acceleration", "preshared_key_storage"], k)]) == 0
    error_message = "vpn has keys the network-hub stage does not accept: ${join(", ", [for k in try(keys(var.vpn), []) : k if !contains(["customer_gateway_ip", "customer_gateway_bgp_asn", "static_routes_only", "onprem_cidrs", "tunnel_inside_cidrs", "enable_acceleration", "preshared_key_storage"], k)])}."
  }
}

variable "spoke_attachments" {
  description = "Workload spoke attachments the hub accepts, associates with their segment table (prod or nonprod) and propagates into the inspection table (without the Network Firewall, the starter profile: the shared table, and egress is NAT only, not inspected): map of name to {attachment_id, segment, accept (default true), cidr}. attachment_id is the aws-workload-<env> output tgw_attachment_id. cidr (default aws.workload_environments.<key>.vpc_cidr) is blackholed in the other segment's table, so prod and nonprod spokes cannot reach each other. Null = aws.network.spoke_attachments from config/landing-zone.yaml, else none. See docs/architecture/aws-landing-zone.md."
  type = map(object({
    attachment_id = string
    segment       = string
    accept        = optional(bool, true)
    cidr          = optional(string)
  }))
  default = null
}
