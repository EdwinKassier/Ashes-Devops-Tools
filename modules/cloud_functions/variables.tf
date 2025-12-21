variable "project_id" {
  description = "The ID of the project where the Cloud Function will be created"
  type        = string

  validation {
    condition     = length(var.project_id) >= 6 && length(var.project_id) <= 30
    error_message = "Project ID must be between 6 and 30 characters"
  }
}

variable "function_name" {
  description = "The name of the Cloud Function"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens"
  }
}

variable "description" {
  description = "Description of the Cloud Function"
  type        = string
  default     = ""
}

variable "runtime" {
  description = "The runtime in which the function will execute (e.g., python310, nodejs18, go119)"
  type        = string
  default     = "python310"

  validation {
    condition = contains([
      "python38", "python39", "python310", "python311",
      "nodejs16", "nodejs18", "nodejs20",
      "go116", "go118", "go119", "go120", "go121",
      "java11", "java17",
      "dotnet3", "dotnet6",
      "ruby30", "ruby32",
      "php81", "php82"
    ], var.runtime)
    error_message = "Runtime must be a valid Cloud Functions runtime"
  }
}

variable "region" {
  description = "The region where the Cloud Function will be created"
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format"
  }
}

variable "bucket_location" {
  description = "The location for the source code bucket (can be region or multi-region)"
  type        = string
  default     = "US"
}

variable "memory_mb" {
  description = "Memory (in MB) for the Cloud Function"
  type        = number
  default     = 256

  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.memory_mb)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB"
  }
}

variable "timeout_seconds" {
  description = "Timeout (in seconds) for the Cloud Function"
  type        = number
  default     = 60

  validation {
    condition     = var.timeout_seconds > 0 && var.timeout_seconds <= 540
    error_message = "Timeout must be between 1 and 540 seconds"
  }
}

variable "entry_point" {
  description = "The name of the function (as defined in source code) that will be executed"
  type        = string
}

variable "service_account_email" {
  description = "The service account email to run the function as"
  type        = string
  default     = ""
}

variable "environment_variables" {
  description = "A map of environment variables to pass to the function"
  type        = map(string)
  default     = {}
}

variable "vpc_connector" {
  description = "The VPC Network Connector that this cloud function can connect to (format: projects/PROJECT/locations/REGION/connectors/CONNECTOR)"
  type        = string
  default     = ""
}

variable "vpc_egress_settings" {
  description = "VPC egress settings for the function"
  type        = string
  default     = "PRIVATE_RANGES_ONLY"

  validation {
    condition     = contains(["PRIVATE_RANGES_ONLY", "ALL_TRAFFIC"], var.vpc_egress_settings)
    error_message = "VPC egress settings must be either PRIVATE_RANGES_ONLY or ALL_TRAFFIC"
  }
}

variable "labels" {
  description = "A map of labels to apply to the Cloud Function"
  type        = map(string)
  default     = {}
}

variable "allowed_invokers" {
  description = "List of IAM members who can invoke the function (e.g., ['user:email@example.com', 'serviceAccount:sa@project.iam.gserviceaccount.com'])"
  type        = list(string)
  default     = []
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated invocations (NOT RECOMMENDED for production)"
  type        = bool
  default     = false

  validation {
    condition     = var.allow_unauthenticated == false
    error_message = "Public access (allow_unauthenticated=true) is restricted. Check your security policy."
  }
}

variable "logs_bucket_name" {
  description = "The name of the bucket to store logs"
  type        = string
}

variable "kms_key_name" {
  description = "The full name of the KMS key to use for encryption (format: projects/PROJECT/locations/LOCATION/keyRings/KEYRING/cryptoKeys/KEY)"
  type        = string
  default     = ""
}

variable "source_archive_path" {
  description = "The path to the source code archive (ZIP file)"
  type        = string
  default     = "./function-source.zip"
}

variable "trigger_http" {
  description = "Whether to trigger the function via HTTP request"
  type        = bool
  default     = true
}

variable "event_trigger_type" {
  description = "The type of event to trigger the function (e.g., google.storage.object.finalize)"
  type        = string
  default     = ""
}

variable "event_trigger_resource" {
  description = "The resource that triggers the function (e.g., projects/PROJECT/buckets/BUCKET)"
  type        = string
  default     = ""
}

variable "event_trigger_retry" {
  description = "Whether to retry on failure for event-triggered functions"
  type        = bool
  default     = false
}
