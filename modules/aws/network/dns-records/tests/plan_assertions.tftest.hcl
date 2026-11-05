mock_provider "aws" {}

variables {
  zone_id = "Z0123456789ABCDEFGHIJ"
}

run "no_records_by_default" {
  command = plan

  assert {
    condition     = length(aws_route53_record.this) == 0
    error_message = "with an empty records map the module must create nothing."
  }
}

run "creates_saas_records_in_existing_zone" {
  command = plan

  variables {
    records = {
      vercel_app = { name = "app.example.com", type = "CNAME", records = ["cname.vercel-dns.com"] }
      supabase   = { name = "db.example.com", type = "CNAME", records = ["abcdref.supabase.co"] }
      vercel_txt = { name = "_vercel.example.com", type = "TXT", ttl = 60, records = ["vc-domain-verify=xyz"] }
    }
  }

  assert {
    condition     = length(aws_route53_record.this) == 3
    error_message = "one record must be created per records entry."
  }

  # Records land in the provided EXISTING zone (not a zone this module creates).
  assert {
    condition     = aws_route53_record.this["vercel_app"].zone_id == "Z0123456789ABCDEFGHIJ"
    error_message = "records must be written into the provided existing hosted zone."
  }

  assert {
    condition     = aws_route53_record.this["vercel_app"].type == "CNAME" && contains(aws_route53_record.this["vercel_app"].records, "cname.vercel-dns.com")
    error_message = "the Vercel record must be a CNAME to cname.vercel-dns.com."
  }
}
