variable "project_id" {
  description = "GCP project that holds the Cloud DNS managed zone."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

variable "managed_zone" {
  description = "Name of the EXISTING Cloud DNS managed zone to write records into (not the DNS name). The zone must already exist in var.project_id."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.managed_zone))
    error_message = "managed_zone must be a valid Cloud DNS managed-zone name (lowercase letters, digits, hyphens)."
  }
}

variable "records" {
  description = <<-EOT
    DNS record sets to create in the zone, keyed by a label. Default empty (creates
    nothing). Each entry sets the record name (a fully qualified name ending in a
    dot), type, ttl, and rrdatas. Common SaaS records:
      Vercel subdomain:  { name = "app.example.com.", type = "CNAME", rrdatas = ["cname.vercel-dns.com."] }
      Vercel apex:       { name = "example.com.",     type = "A",     rrdatas = ["76.76.21.21"] }
      Supabase domain:   { name = "db.example.com.",  type = "CNAME", rrdatas = ["<project-ref>.supabase.co."] }
      Verification TXT:  { name = "_vercel.example.com.", type = "TXT", rrdatas = ["\"vc-domain-verify=...\""] }
  EOT
  type = map(object({
    name    = string
    type    = string
    ttl     = optional(number, 300)
    rrdatas = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.records) : endswith(r.name, ".")])
    error_message = "Each record name must be fully qualified and end with a dot, e.g. app.example.com."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : contains(["A", "AAAA", "CNAME", "TXT", "MX", "NS", "SRV", "CAA"], r.type)])
    error_message = "Each record type must be one of A, AAAA, CNAME, TXT, MX, NS, SRV, CAA."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : length(r.rrdatas) > 0])
    error_message = "Each record must have at least one rrdata value."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.ttl >= 0 && r.ttl <= 2147483647])
    error_message = "Each record ttl must be a non-negative integer within the DNS TTL range."
  }
}
