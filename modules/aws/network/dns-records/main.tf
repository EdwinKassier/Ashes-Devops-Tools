# Write DNS records into an EXISTING Route 53 hosted zone (audit H9, option C —
# DNS unification, AWS counterpart of modules/gcp/network/dns-records). This
# module does NOT create the hosted zone: it adds records to a zone managed
# elsewhere (a registrar-delegated public zone, or one created by another root).
# Use it to keep SaaS custom-domain records (Vercel, Supabase) in the org's
# managed zone instead of a separate registrar.
#
# Opt-in: with an empty records map it creates nothing. Simple (non-alias)
# records only; alias records are out of scope.

resource "aws_route53_record" "this" {
  for_each = var.records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}
