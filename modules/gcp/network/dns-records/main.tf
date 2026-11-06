# Write DNS record sets into an EXISTING Cloud DNS managed zone (DNS
# unification). Unlike modules/gcp/network/dns, this module does NOT own
# the zone: it adds records to a zone created elsewhere (the host stage, the hub,
# or a registrar-delegated public zone). Use it to keep SaaS custom-domain records
# (Vercel, Supabase) in the org's managed zone instead of a separate registrar.
#
# Opt-in: with an empty records map it creates nothing.

resource "google_dns_record_set" "this" {
  for_each = var.records

  project      = var.project_id
  managed_zone = var.managed_zone
  name         = each.value.name
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.rrdatas
}
