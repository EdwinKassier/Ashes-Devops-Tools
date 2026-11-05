mock_provider "aws" {}

variables {
  zone_id = "Z0123456789ABCDEFGHIJ"
}

run "rejects_bad_zone_id" {
  command = plan
  variables {
    zone_id = "not-a-zone"
  }
  expect_failures = [var.zone_id]
}

run "rejects_bad_record_type" {
  command = plan
  variables {
    records = { web = { name = "app.example.com", type = "WEIRD", records = ["x"] } }
  }
  expect_failures = [var.records]
}

run "rejects_empty_records_values" {
  command = plan
  variables {
    records = { web = { name = "app.example.com", type = "CNAME", records = [] } }
  }
  expect_failures = [var.records]
}

run "rejects_empty_name" {
  command = plan
  variables {
    records = { web = { name = "  ", type = "CNAME", records = ["cname.vercel-dns.com"] } }
  }
  expect_failures = [var.records]
}
