variable "zone_id" {
  description = "ID of the EXISTING Route 53 hosted zone to write records into (e.g. Z0123456789ABCDEFGHIJ). The zone must already exist."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID (starts with Z, uppercase letters and digits)."
  }
}

variable "records" {
  description = <<-EOT
    DNS records to create in the hosted zone, keyed by a label. Default empty
    (creates nothing). Each entry sets the record name, type, ttl, and records
    (the rrdata values). Common SaaS records:
      Vercel subdomain:  { name = "app.example.com", type = "CNAME", records = ["cname.vercel-dns.com"] }
      Vercel apex:       { name = "example.com",     type = "A",     records = ["76.76.21.21"] }
      Supabase domain:   { name = "db.example.com",  type = "CNAME", records = ["<project-ref>.supabase.co"] }
      Verification TXT:  { name = "_vercel.example.com", type = "TXT", records = ["vc-domain-verify=..."] }
  EOT
  type = map(object({
    name    = string
    type    = string
    ttl     = optional(number, 300)
    records = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.records) : contains(["A", "AAAA", "CNAME", "TXT", "MX", "NS", "SRV", "CAA"], r.type)])
    error_message = "Each record type must be one of A, AAAA, CNAME, TXT, MX, NS, SRV, CAA."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : length(r.records) > 0])
    error_message = "Each record must have at least one value in records."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : length(trimspace(r.name)) > 0])
    error_message = "Each record must have a non-empty name."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.ttl >= 0 && r.ttl <= 2147483647])
    error_message = "Each record ttl must be a non-negative integer within the DNS TTL range."
  }
}
