# -----------------------------------------------------------------------------
# Naming + tagging
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment this workload account serves (e.g. dev, staging, prod). Used to derive the default resource name workload-<environment>. null keeps the legacy name \"workload\"."
  type        = string
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z][a-z0-9-]{0,30}$", coalesce(var.environment, "x")))
    error_message = "environment must be null or a lowercase name (letters, digits, hyphens; max 31 chars)."
  }
}

variable "name" {
  description = "Name of the spoke VPC (and prefix for its subnets, route tables and TGW attachment). null derives workload-<environment> (or \"workload\" when environment is null)."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || length(trimspace(coalesce(var.name, " "))) > 0
    error_message = "name must be null or a non-empty string."
  }
}

variable "tags" {
  description = "Tags applied to the stage's own taggable resources (spoke VPC and its children, TGW attachment). Org-wide tags (CostCenter, Environment, Owner, ...) normally come from the provider default_tags; use this for stage-specific additions."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Region + addressing
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region the workload's spoke VPC is deployed in and the region the default provider operates in. Used for subnet math and gateway-endpoint service names."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region id (e.g. eu-west-2)."
  }
}

variable "aws_enabled_regions" {
  description = "Regions in which to enforce the account baseline (default EBS encryption) and deploy a Config recorder. Defaults to the single home Region."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one region."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the workload spoke VPC. Used for subnet math; also the literal VPC CIDR when ipam_pool_id is empty."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.20.0.0/16)."
  }
}

variable "ipam_pool_id" {
  description = "IPAM pool ID to allocate the spoke VPC CIDR from (the network account's regional pool, shared over RAM). Empty string uses the literal vpc_cidr instead."
  type        = string
  default     = ""
}

variable "availability_zones" {
  description = "Availability zones to spread each subnet tier across. Only the first az_count entries are used."
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "availability_zones must contain at least one zone."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread each subnet tier across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }

  validation {
    condition     = var.az_count <= length(var.availability_zones)
    error_message = "az_count must not exceed the number of availability_zones provided."
  }
}

variable "subnets" {
  description = "Spoke subnet tiers, keyed by tier name. newbits/number_offset drive cidrsubnet(vpc_cidr, newbits, number_offset + az_index); the tgw tier holds the transit-gateway attachment ENIs. Offsets are multiples of 8 (> az_count) so per-AZ subnets never collide."
  type = map(object({
    newbits       = number
    number_offset = number
    public        = optional(bool, false)
  }))
  default = {
    private  = { newbits = 8, number_offset = 0 }
    isolated = { newbits = 8, number_offset = 8 }
    tgw      = { newbits = 8, number_offset = 16 }
  }

  validation {
    condition     = contains(keys(var.subnets), "tgw")
    error_message = "subnets must define a tgw tier for the transit-gateway attachment."
  }
}

variable "enable_public_subnets" {
  description = "Add a public subnet tier (\"public\": newbits 8, number_offset 24, one subnet per AZ) whose route tables default-route to an internet gateway this stage creates. Only for an internet-facing app ALB (aws-workload app_ingress_mode = \"public_alb\"); tasks and databases stay in the private/isolated tiers. Default false: no public subnets, no IGW."
  type        = bool
  default     = false
}

variable "create_internet_gateway" {
  description = "Attach an internet gateway to the spoke VPC even without public subnets (no routes to it are added). CloudFront VPC origins require the origin VPC to have one. Implied by enable_public_subnets."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Shared-network wiring (from the aws-network root's cross-root contract)
# -----------------------------------------------------------------------------

variable "tgw_id" {
  description = "ID of the SHARED transit gateway (shared into this workload account over RAM by the network account) that the spoke VPC attaches to. Null (default) is standalone mode: no TGW attachment and no TGW routes, so the spoke's private/isolated tiers stay local-only (no NAT, no egress) until a network hub exists."
  type        = string
  default     = null

  validation {
    condition     = var.tgw_id == null || can(regex("^tgw-", coalesce(var.tgw_id, "x")))
    error_message = "tgw_id must be null (standalone) or a transit gateway id (tgw-xxxxxxxx)."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the central log-archive S3 bucket that receives the spoke VPC's flow logs."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.flow_log_destination_arn))
    error_message = "flow_log_destination_arn must be an S3 bucket ARN beginning with arn:aws:s3:::."
  }
}

variable "tgw_route_tiers" {
  description = "Spoke subnet tiers whose route tables send tgw_destination_cidrs to the shared transit gateway. Defaults to the private tier; the isolated tier stays local-only by design."
  type        = list(string)
  default     = ["private"]

  validation {
    condition     = alltrue([for t in var.tgw_route_tiers : contains(keys(var.subnets), t)])
    error_message = "Every tgw_route_tiers entry must be a tier defined in subnets."
  }
}

variable "tgw_destination_cidrs" {
  description = "Destination CIDRs routed from tgw_route_tiers to the shared transit gateway. Default 0.0.0.0/0 sends all non-local traffic to the hub (centralized egress + inspection); use the org supernet (e.g. [\"10.0.0.0/8\"]) for east-west only."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.tgw_destination_cidrs : can(cidrnetmask(c))])
    error_message = "Every tgw_destination_cidrs entry must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = length(var.tgw_destination_cidrs) == length(distinct(var.tgw_destination_cidrs))
    error_message = "tgw_destination_cidrs must not contain duplicates."
  }
}

# -----------------------------------------------------------------------------
# Config recorder + logging + KMS
# -----------------------------------------------------------------------------

variable "log_archive_bucket_name" {
  description = "Name of the central log-archive S3 bucket that receives Config snapshots/history and Session Manager session logs."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty S3 bucket name."
  }
}

variable "config_role_arn" {
  description = "ARN of the IAM role AWS Config assumes to record resource configurations in this account/Region. Null (default) uses the account's AWSServiceRoleForConfig service-linked role (created unless create_config_service_linked_role = false)."
  type        = string
  default     = null

  validation {
    condition     = var.config_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.config_role_arn, "x")))
    error_message = "config_role_arn must be null or an account-qualified IAM role ARN."
  }
}

variable "create_config_service_linked_role" {
  description = "With config_role_arn = null, create the AWSServiceRoleForConfig service-linked role in the workload account. Set false if Config was ever enabled in the account (the SLR already exists)."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of the CMK used as the account default EBS encryption key and (when enable_ssm is true) to encrypt Session Manager sessions/logs. Empty string leaves default EBS encryption on the AWS-managed key; must be a non-empty key when enable_ssm is true."
  type        = string
  default     = ""
}

variable "enable_ebs_default_kms_key" {
  description = "Set kms_key_arn as the account default EBS key in the HOME region (aws_region) with a plan-safe count. Use true when kms_key_arn is created in the same plan (its ARN is unknown until apply). Null (default) keeps the legacy behaviour: the account baseline sets it in every aws_enabled_regions entry when kms_key_arn is non-empty. False sets no default key."
  type        = bool
  default     = null
}

# -----------------------------------------------------------------------------
# IAM roles
# -----------------------------------------------------------------------------

variable "workload_roles" {
  description = "Map of workload / cross-account IAM role name to its configuration (trust_policy JSON, managed_policy_arns, inline_policy, etc.). Empty by default."
  type = map(object({
    trust_policy         = string
    max_session_duration = optional(number, 3600)
    managed_policy_arns  = optional(list(string), [])
    inline_policy        = optional(string, "")
    permissions_boundary = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Optional components
# -----------------------------------------------------------------------------

variable "enable_ssm" {
  description = "Deploy the Systems Manager baseline (Session Manager preferences, patch baseline, inventory). On by default. Requires a non-empty kms_key_arn (Session Manager sessions/logs are KMS-encrypted; an empty key would leave the session document's kmsKeyId blank)."
  type        = bool
  default     = true

  validation {
    # Guardrail: enabling SSM with an empty kms_key_arn would produce a Session
    # Manager document with an empty kmsKeyId, i.e. sessions NOT encrypted in
    # transit (CKV_AWS_112). Require a real CMK whenever SSM is on.
    condition     = !var.enable_ssm || length(trimspace(var.kms_key_arn)) > 0
    error_message = "kms_key_arn must be a non-empty CMK ARN when enable_ssm is true (Session Manager sessions must be KMS-encrypted)."
  }
}

variable "enable_edge" {
  description = "Deploy the per-workload edge-security stack (CloudFront + WAF, in us-east-1). Off by default; a workload opts in when it fronts an internet-facing app."
  type        = bool
  default     = false
}

variable "edge_name_prefix" {
  description = "Prefix applied to the edge WAF Web ACL, CloudFront Shield protection, and metric names. Ignored when enable_edge is false."
  type        = string
  default     = "workload-edge"

  validation {
    condition     = length(trimspace(var.edge_name_prefix)) > 0
    error_message = "edge_name_prefix must be a non-empty string."
  }
}

variable "edge_origin_domain_name" {
  description = "DNS name of the origin the edge CloudFront distribution fetches from. Ignored when enable_edge is false."
  type        = string
  default     = "origin.example.com"
}

variable "tfc_apply_boundary_policy_name" {
  description = "Name of the tfc-apply permissions-boundary managed policy (tfc-oidc-baseline apply_boundary_policy_name). Every IAM role this stage creates in the workload account (workload_roles without their own permissions_boundary) gets permissions_boundary = arn:PARTITION:iam::ACCOUNT_ID:policy/NAME, derived from that account's provider, which the member-account tfc-apply role requires when boundary propagation is on. Null = create roles without a boundary."
  type        = string
  default     = "tfc-apply-boundary"

  validation {
    condition     = var.tfc_apply_boundary_policy_name == null || can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.tfc_apply_boundary_policy_name))
    error_message = "tfc_apply_boundary_policy_name must be null or a valid IAM policy name (1-128 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "enable_vpc_bpa_exclusion" {
  description = "Create a VPC Block Public Access exclusion (allow-bidirectional) for this spoke VPC so an internet-facing ALB in its public tier can receive traffic. The org declarative EC2 policy blocks internet-gateway ingress for every VPC; an exclusion is only accepted when aws-organization sets allow_vpc_bpa_exclusions = true. Scoped to this one VPC. Default false."
  type        = bool
  default     = false
}
