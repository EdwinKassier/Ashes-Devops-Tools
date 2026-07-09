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
  description = "ARN of the IAM role Config assumes to record resource configurations in each account/Region."
  type        = string

  validation {
    condition     = length(trimspace(var.config_role_arn)) > 0
    error_message = "config_role_arn must be a non-empty IAM role ARN."
  }
}

variable "log_archive_bucket" {
  description = "Name of the central log-archive S3 bucket that receives Config configuration snapshots and history."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket)) > 0
    error_message = "log_archive_bucket must be a non-empty S3 bucket name."
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
  description = "ARN of the IAM role the aggregator assumes to collect Config data across the organization. Required unless recorder_only = true; defaults to an empty string because the aggregator is not created in recorder_only mode."
  type        = string
  default     = ""
}

variable "conformance_packs" {
  description = "Opt-in bring-your-own-pack hook: map of organization conformance packs to deploy (e.g. a NIST 800-53 sample YAML), keyed by pack name. Provide exactly one of template_body or template_s3_uri per pack. No packs are bundled with this module. Ignored when recorder_only = true."
  type = map(object({
    template_body   = optional(string)
    template_s3_uri = optional(string)
  }))
  default = {}
}
