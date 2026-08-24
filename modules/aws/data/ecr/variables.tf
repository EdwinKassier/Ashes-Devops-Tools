variable "repositories" {
  description = "Map of ECR repositories to create, keyed by repository name. The parity counterpart to GCP's artifact-registry."
  type = map(object({
    image_tag_mutability = optional(string, "IMMUTABLE")
    scan_on_push         = optional(bool, true)
    kms_key_arn          = optional(string) # null => AES256; set => KMS encryption
    force_delete         = optional(bool, false)
    # Optional lifecycle policy: expire untagged images older than N days and/or
    # keep only the most recent N tagged images. Rendered to JSON via jsonencode.
    expire_untagged_after_days = optional(number)
    keep_last_tagged_images    = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.repositories) : contains(["MUTABLE", "IMMUTABLE"], r.image_tag_mutability)
    ])
    error_message = "Each repository image_tag_mutability must be MUTABLE or IMMUTABLE."
  }

  validation {
    condition = alltrue([
      for r in values(var.repositories) : r.expire_untagged_after_days == null || r.expire_untagged_after_days >= 1
    ])
    error_message = "expire_untagged_after_days, when set, must be >= 1."
  }

  validation {
    condition = alltrue([
      for r in values(var.repositories) : r.keep_last_tagged_images == null || r.keep_last_tagged_images >= 1
    ])
    error_message = "keep_last_tagged_images, when set, must be >= 1."
  }
}

variable "org_id" {
  description = "AWS Organizations ID (o-xxxx). When set, an org-scoped repository policy (aws:PrincipalOrgID) granting pull access to the org is attached to every repository. Null = no repository policy."
  type        = string
  default     = null

  validation {
    condition     = var.org_id == null || can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be null or a valid AWS Organizations ID (o-xxxxxxxxxx)."
  }
}

variable "tags" {
  description = "Tags applied to every repository."
  type        = map(string)
  default     = {}
}
