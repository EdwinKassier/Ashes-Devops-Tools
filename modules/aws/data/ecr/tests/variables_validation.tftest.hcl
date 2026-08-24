# Variable validation tests for the data/ecr module (mock_provider — no creds).

mock_provider "aws" {}

run "accepts_empty_defaults" {
  command = plan
}

run "rejects_bad_image_tag_mutability" {
  command = plan

  expect_failures = [var.repositories]

  variables {
    repositories = {
      "bad" = { image_tag_mutability = "SOMETIMES" }
    }
  }
}

run "rejects_zero_expire_days" {
  command = plan

  expect_failures = [var.repositories]

  variables {
    repositories = {
      "bad" = { expire_untagged_after_days = 0 }
    }
  }
}

run "rejects_bad_org_id" {
  command = plan

  expect_failures = [var.org_id]

  variables {
    org_id = "my-org"
  }
}
