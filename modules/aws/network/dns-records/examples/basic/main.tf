# Basic working example for the aws/dns-records module.
# Writes SaaS custom-domain records (a Vercel app subdomain, a Supabase custom
# domain and a Vercel verification TXT record) into an EXISTING Route 53 hosted
# zone. The module never creates the zone. Run `terraform init && terraform
# validate` here to check it.
#
# The zone ID, domain names and record values are placeholders: replace them
# with your own zone and the values your SaaS providers give you.

module "dns_records" {
  source = "../../"

  zone_id = "Z0123456789ABCDEFGHIJ"

  records = {
    vercel_app = {
      name    = "app.example.com"
      type    = "CNAME"
      records = ["cname.vercel-dns.com"]
    }
    supabase = {
      name    = "db.example.com"
      type    = "CNAME"
      records = ["abcdefghijklmnopqrst.supabase.co"]
    }
    vercel_txt = {
      name    = "_vercel.example.com"
      type    = "TXT"
      ttl     = 60
      records = ["vc-domain-verify=app.example.com,0123456789abcdef"]
    }
  }
}
