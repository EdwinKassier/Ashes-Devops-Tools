mock_provider "google" {}

variables {
  project_id = "acme-audit-abcd"
}

run "rejects_bad_project_id" {
  command = plan
  variables {
    project_id = "X"
  }
  expect_failures = [var.project_id]
}

run "rejects_bad_email" {
  command = plan
  variables {
    notification_email_addresses = ["not-an-email"]
  }
  expect_failures = [var.notification_email_addresses]
}

run "rejects_invalid_watch_severity" {
  command = plan
  variables {
    watches = {
      bad = { display_name = "Bad", filter = "protoPayload.methodName=\"X\"", severity = "LOUD" }
    }
  }
  expect_failures = [var.watches]
}

run "rejects_empty_watch_filter" {
  command = plan
  variables {
    watches = {
      empty = { display_name = "Empty", filter = "  " }
    }
  }
  expect_failures = [var.watches]
}

run "rejects_out_of_range_rate_limit" {
  command = plan
  variables {
    notification_rate_limit_seconds = 99999
  }
  expect_failures = [var.notification_rate_limit_seconds]
}

run "rejects_non_numeric_org_id" {
  command = plan

  variables {
    org_id = "organizations/123"
  }

  expect_failures = [var.org_id]
}

run "rejects_bad_break_glass_email" {
  command = plan

  variables {
    break_glass_principal_emails = ["not-an-email"]
  }

  expect_failures = [var.break_glass_principal_emails]
}
