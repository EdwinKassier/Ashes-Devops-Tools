variable "description" {
  description = "Description applied to the transit gateway; also used as its Name tag."
  type        = string
  default     = "org-tgw"

  validation {
    condition     = length(trimspace(var.description)) > 0
    error_message = "description must be a non-empty string."
  }
}

variable "route_tables" {
  description = "Segment route tables to create on the transit gateway. Each attachment associates with exactly one of these segments."
  type        = list(string)
  default     = ["prod", "nonprod", "inspection", "shared"]

  validation {
    condition     = length(var.route_tables) > 0
    error_message = "route_tables must define at least one segment."
  }

  validation {
    condition     = length(var.route_tables) == length(toset(var.route_tables))
    error_message = "route_tables must not contain duplicate segment names."
  }
}

variable "attachments" {
  description = "VPC attachments keyed by attachment name. segment must be one of route_tables. appliance_mode enables symmetric routing (set true on the inspection attachment)."
  type = map(object({
    vpc_id         = string
    subnet_ids     = list(string)
    segment        = string
    appliance_mode = optional(bool, false)
  }))
  default = {
    inspection = {
      vpc_id         = "vpc-inspection0000000"
      subnet_ids     = ["subnet-insp0a", "subnet-insp0b"]
      segment        = "inspection"
      appliance_mode = true
    }
    prod = {
      vpc_id     = "vpc-prod00000000000"
      subnet_ids = ["subnet-prod0a", "subnet-prod0b"]
      segment    = "prod"
    }
    nonprod = {
      vpc_id     = "vpc-nonprod00000000"
      subnet_ids = ["subnet-nonp0a", "subnet-nonp0b"]
      segment    = "nonprod"
    }
  }

  validation {
    # Every attachment's segment must correspond to a declared route table,
    # otherwise the association/route lookups would reference a missing table.
    condition     = alltrue([for a in values(var.attachments) : contains(var.route_tables, a.segment)])
    error_message = "Every attachment segment must be one of route_tables."
  }
}

variable "propagations" {
  description = "Route-table propagations keyed by a plan-known string (e.g. \"prod->shared\"). attachment names a var.attachments key; route_table names a var.route_tables entry. prod<->nonprod pairings are deliberately omitted to enforce isolation."
  type = map(object({
    attachment  = string
    route_table = string
  }))
  default = {
    # prod and nonprod both propagate into the shared route table, so shared
    # services learn routes to both. The inspection attachment propagates into
    # the prod and nonprod tables so their default route can resolve to the
    # firewall. prod and nonprod NEVER propagate into each other's tables, so
    # they cannot reach each other (there is no default table to leak routes).
    "prod->shared"        = { attachment = "prod", route_table = "shared" }
    "nonprod->shared"     = { attachment = "nonprod", route_table = "shared" }
    "inspection->prod"    = { attachment = "inspection", route_table = "prod" }
    "inspection->nonprod" = { attachment = "inspection", route_table = "nonprod" }
  }
}

variable "routes" {
  description = "Static routes keyed by a plan-known string. cidr is the destination; attachment (a var.attachments key) is the next hop; blackhole drops the traffic. Set exactly one of attachment or blackhole per route."
  type = map(object({
    route_table = string
    cidr        = string
    attachment  = optional(string)
    blackhole   = optional(bool, false)
  }))
  default = {
    # Default route for prod and nonprod segments points at the inspection
    # attachment so east-west/egress traffic is forced through the firewall.
    "prod:default"    = { route_table = "prod", cidr = "0.0.0.0/0", attachment = "inspection" }
    "nonprod:default" = { route_table = "nonprod", cidr = "0.0.0.0/0", attachment = "inspection" }
  }
}

variable "share_name" {
  description = "Name of the RAM resource share used to share the transit gateway across the organization."
  type        = string
  default     = "tgw-share"

  validation {
    condition     = length(trimspace(var.share_name)) > 0
    error_message = "share_name must be a non-empty string."
  }
}

variable "org_arn" {
  description = "ARN of the AWS Organization (or an OU) to grant access to the shared transit gateway via RAM."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:organizations::", var.org_arn))
    error_message = "org_arn must be an AWS Organizations ARN beginning with arn:aws:organizations::."
  }
}
