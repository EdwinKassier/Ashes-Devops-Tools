mock_provider "google" {}

variables {
  project_id   = "acme-dns-abcd"
  managed_zone = "example-com"
}

run "rejects_non_fqdn_record_name" {
  command = plan
  variables {
    records = { web = { name = "app.example.com", type = "CNAME", rrdatas = ["cname.vercel-dns.com."] } }
  }
  expect_failures = [var.records]
}

run "rejects_bad_record_type" {
  command = plan
  variables {
    records = { web = { name = "app.example.com.", type = "WEIRD", rrdatas = ["x."] } }
  }
  expect_failures = [var.records]
}

run "rejects_empty_rrdatas" {
  command = plan
  variables {
    records = { web = { name = "app.example.com.", type = "CNAME", rrdatas = [] } }
  }
  expect_failures = [var.records]
}

run "rejects_bad_managed_zone" {
  command = plan
  variables {
    managed_zone = "Example_Zone"
  }
  expect_failures = [var.managed_zone]
}
