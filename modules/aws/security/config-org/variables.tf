# -----------------------------------------------------------------------------
# Region topology
# -----------------------------------------------------------------------------

variable "aws_enabled_regions" {
  description = "Regions in which to deploy a Config recorder, delivery channel, and recorder status. One set of per-Region resources is created for each entry."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one Region."
  }

  validation {
    condition     = length(var.aws_enabled_regions) == length(distinct(var.aws_enabled_regions))
    error_message = "aws_enabled_regions must not contain duplicate Regions."
  }
}

# -----------------------------------------------------------------------------
# Recorder / delivery-channel configuration
# -----------------------------------------------------------------------------

variable "recorder_name" {
  description = "Name applied to every per-Region configuration recorder."
  type        = string
  default     = "org-recorder"
}

variable "delivery_channel_name" {
  description = "Name applied to every per-Region delivery channel."
  type        = string
  default     = "org-delivery"
}

variable "config_role_arn" {
  description = "ARN of the IAM role Config assumes to record resource configurations in each account/Region. Null (default) uses the account's AWS Config service-linked role AWSServiceRoleForConfig (AWS-recommended), created here when create_service_linked_role = true."
  type        = string
  default     = null

  validation {
    condition     = var.config_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.config_role_arn, "x")))
    error_message = "config_role_arn must be null or an account-qualified IAM role ARN."
  }
}

variable "create_service_linked_role" {
  description = "With config_role_arn = null, create the AWSServiceRoleForConfig service-linked role (aws_iam_service_linked_role). Default true for freshly vended accounts; set false when the account already has it (Config was enabled before, e.g. by Control Tower or the console) — the recorder then references the existing role by its well-known ARN. Ignored when config_role_arn is set."
  type        = bool
  default     = true
}

variable "log_archive_bucket" {
  description = "Name of the central log-archive S3 bucket that receives Config configuration snapshots and history."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket)) > 0
    error_message = "log_archive_bucket must be a non-empty S3 bucket name."
  }
}

variable "home_region" {
  description = "Home (aggregation) Region. Global resource types (IAM, etc.) are recorded ONLY by the recorder in this Region to avoid duplicating global configuration items in every Region. Must be one of aws_enabled_regions for global types to be recorded at all."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = length(trimspace(var.home_region)) > 0
    error_message = "home_region must be a non-empty Region name."
  }
}

variable "record_all_supported" {
  description = "COST TOGGLE. When true (default), each recorder records ALL supported resource types (and, being all_supported, global resource types too). Recording every resource type in every Region is the most expensive Config mode; set false to pair with a narrower recording_group managed out-of-band when cost matters."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Organization aggregator + conformance packs (gated by recorder_only)
# -----------------------------------------------------------------------------

variable "recorder_only" {
  description = "When true, deploy only the per-Region recorder/delivery-channel/status and skip the org aggregator and conformance packs. The aws-workload stage sets this true to deploy a single workload account's recorder; the home-account aws-config stage leaves it false."
  type        = bool
  default     = false
}

variable "aggregator_name" {
  description = "Name of the organization configuration aggregator. Ignored when recorder_only = true."
  type        = string
  default     = "org-aggregator"
}

variable "aggregator_role_arn" {
  description = "ARN of an existing IAM role the organization aggregator assumes to collect Config data across the organization. Null or \"\" (default) creates one here (aggregator_role_name, trusting config.amazonaws.com, with the AWS managed policy AWSConfigRoleForOrganizations) unless recorder_only = true, where no aggregator exists."
  type        = string
  default     = null

  validation {
    condition     = var.aggregator_role_arn == null || var.aggregator_role_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", coalesce(var.aggregator_role_arn, "x")))
    error_message = "aggregator_role_arn must be null, empty, or an account-qualified IAM role ARN."
  }
}

variable "account_id" {
  description = "12-digit ID of the account the recorders run in, used to build the service-linked-role ARN when config_role_arn = null. Null = read from aws_caller_identity."
  type        = string
  default     = null

  validation {
    condition     = var.account_id == null || can(regex("^[0-9]{12}$", coalesce(var.account_id, "x")))
    error_message = "account_id must be null or a 12-digit AWS account ID."
  }
}

variable "partition" {
  description = "AWS partition used to build the managed-policy and pre-existing service-linked-role ARNs (aws, aws-us-gov, aws-cn)."
  type        = string
  default     = "aws"

  validation {
    condition     = can(regex("^aws(-[a-z]+)*$", var.partition))
    error_message = "partition must be aws, aws-us-gov, aws-cn, ..."
  }
}

variable "aggregator_role_name" {
  description = "Name of the aggregator IAM role created when aggregator_role_arn is null/empty and recorder_only = false."
  type        = string
  default     = "aws-config-org-aggregator"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.aggregator_role_name))
    error_message = "aggregator_role_name must be a valid IAM role name (1-64 chars of [A-Za-z0-9+=,.@_-])."
  }
}

variable "conformance_packs" {
  description = "Opt-in bring-your-own-pack hook: map of organization conformance packs to deploy (e.g. a NIST 800-53 sample YAML), keyed by pack name. Provide exactly one of template_body or template_s3_uri per pack. No packs are bundled with this module. Ignored when recorder_only = true."
  type = map(object({
    template_body   = optional(string)
    template_s3_uri = optional(string)
  }))
  default = {}
}

variable "permissions_boundary_arn" {
  description = "Permissions-boundary managed policy ARN set on every IAM role this module creates. Required when the roles are created by a member-account tfc-apply role with boundary propagation on (tfc-oidc-baseline enable_apply_boundary_propagation): pass arn:PARTITION:iam::ACCOUNT_ID:policy/tfc-apply-boundary. Null (default) = no boundary."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:[^:]+:iam::[^:]*:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be null or an IAM managed policy ARN (arn:PARTITION:iam::ACCOUNT_ID:policy/NAME)."
  }
}
