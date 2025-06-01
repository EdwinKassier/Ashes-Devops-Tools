variable "project_id" {
  description = "The ID of the project where the Cloud Function will be created"
  type        = string
}

variable "function_name" {
  description = "The name of the Cloud Function"
  type        = string
}

variable "description" {
  description = "Description of the Cloud Function"
  type        = string
  default     = ""
}

variable "runtime" {
  description = "The runtime in which the function will execute"
  type        = string
  default     = "python39"
}

variable "region" {
  description = "The region where the Cloud Function will be created"
  type        = string
  default     = "us-central1"
}

variable "memory_mb" {
  description = "Memory (in MB) for the Cloud Function"
  type        = number
  default     = 256
}

variable "timeout_seconds" {
  description = "Timeout (in seconds) for the Cloud Function"
  type        = number
  default     = 60
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
  description = "The VPC Network Connector that this cloud function can connect to"
  type        = string
  default     = ""
}

variable "labels" {
  description = "A map of labels to apply to the Cloud Function"
  type        = map(string)
  default     = {}
}

variable "allowed_invokers" {
  description = "List of IAM members who can invoke the function"
  type        = list(string)
  default     = []
}

variable "logs_bucket_name" {
  description = "The name of the bucket to store logs"
  type        = string
}

variable "kms_key_name" {
  description = "The name of the KMS key to use for encryption"
  type        = string
  default     = ""
}

variable "source_archive_path" {
  description = "The path to the source code archive"
  type        = string
  default     = "./function-source.zip"
}