variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com')"
  type        = string
}

variable "business_units" {
  description = "Map of business units and their configurations"
  type        = map(map(string))
  default = {
    "infrastructure" = {}
    "platform"       = {}
    "security"       = {}
    "workloads"      = {}
  }
}

variable "environments" {
  description = "List of environments to create under each business unit"
  type        = list(string)
  default     = ["development", "staging", "production"]
}