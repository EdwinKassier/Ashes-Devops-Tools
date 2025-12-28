variable "org_id" {
  description = "The organization ID where SCC is enabled"
  type        = string
}

variable "project_id" {
  description = "The project ID where the Pub/Sub topic will be created"
  type        = string
}

variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for SCC notifications"
  type        = string
  default     = "scc-notifications"
}

variable "config_id" {
  description = "ID for the notification config"
  type        = string
  default     = "scc-notification-config"
}

variable "description" {
  description = "Description of the notification config"
  type        = string
  default     = "SCC notifications for active findings"
}

variable "filter" {
  description = "The filter string to trigger notifications"
  type        = string
  default     = "state=\"ACTIVE\""
}
