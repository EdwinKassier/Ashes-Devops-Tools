variable "org_id" {
  description = "The Organization ID where tags will be defined"
  type        = string
}

variable "tags" {
  description = "Map of Tag Keys to a list of allowed Tag Values"
  type        = map(list(string))
  # Example:
  # {
  #   "environment" = ["dev", "prod", "uat"]
  #   "cost-center" = ["engineering", "marketing"]
  # }
}
