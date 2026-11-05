mock_provider "google" {}

variables {
  project_id   = "acme-dns-abcd"
  managed_zone = "example-com"
}

run "no_records_by_default" {
  command = plan

  assert {
    condition     = length(google_dns_record_set.this) == 0
    error_message = "with an empty records map the module must create nothing."
  }
}

run "creates_saas_records_in_existing_zone" {
  command = plan

  variables {
    records = {
      vercel_app = { name = "app.example.com.", type = "CNAME", rrdatas = ["cname.vercel-dns.com."] }
      supabase   = { name = "db.example.com.", type = "CNAME", rrdatas = ["abcdref.supabase.co."] }
      vercel_txt = { name = "_vercel.example.com.", type = "TXT", ttl = 60, rrdatas = ["\"vc-domain-verify=xyz\""] }
    }
  }

  assert {
    condition     = length(google_dns_record_set.this) == 3
    error_message = "one record set must be created per records entry."
  }

  # Records land in the provided EXISTING zone (not a zone this module creates).
  assert {
    condition     = google_dns_record_set.this["vercel_app"].managed_zone == "example-com"
    error_message = "records must be written into the provided existing managed zone."
  }

  assert {
    condition     = google_dns_record_set.this["vercel_app"].type == "CNAME" && contains(google_dns_record_set.this["vercel_app"].rrdatas, "cname.vercel-dns.com.")
    error_message = "the Vercel record must be a CNAME to cname.vercel-dns.com."
  }
}
