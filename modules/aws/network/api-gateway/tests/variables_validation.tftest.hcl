# Variable validation tests for the api-gateway module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

variables {
  name = "orders-api"
}

# ── var.name ──────────────────────────────────────────────────────────────────

run "valid_name_accepted" {
  command = plan

  variables {
    name = "orders-api"
  }
}

run "invalid_name_rejected" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "orders api with spaces"
  }
}

# ── var.protocol_type ─────────────────────────────────────────────────────────

run "invalid_protocol_type_rejected" {
  command = plan

  expect_failures = [var.protocol_type]

  variables {
    protocol_type = "GRPC"
  }
}

# ── var.stage_name ────────────────────────────────────────────────────────────

run "default_stage_name_accepted" {
  command = plan

  variables {
    stage_name = "$default"
  }
}

run "invalid_stage_name_rejected" {
  command = plan

  expect_failures = [var.stage_name]

  variables {
    stage_name = "has spaces"
  }
}

# ── var.routes ────────────────────────────────────────────────────────────────

run "invalid_route_integration_type_rejected" {
  command = plan

  expect_failures = [var.routes]

  variables {
    routes = [
      {
        route_key        = "GET /items"
        integration_uri  = "arn:aws:lambda:eu-west-1:123456789012:function:x"
        integration_type = "BOGUS"
      },
    ]
  }
}

# ── var.log_retention_days ────────────────────────────────────────────────────

run "invalid_log_retention_rejected" {
  command = plan

  expect_failures = [var.log_retention_days]

  variables {
    log_retention_days = 12
  }
}

# ── var.kms_key_arn ───────────────────────────────────────────────────────────

run "invalid_kms_key_arn_rejected" {
  command = plan

  expect_failures = [var.kms_key_arn]

  variables {
    kms_key_arn = "not-an-arn"
  }
}

# ── var.certificate_arn ───────────────────────────────────────────────────────

run "invalid_certificate_arn_rejected" {
  command = plan

  expect_failures = [var.certificate_arn]

  variables {
    certificate_arn = "not-an-arn"
  }
}

# ── var.enable_custom_domain cross-variable validation ────────────────────────

run "custom_domain_without_cert_rejected" {
  command = plan

  expect_failures = [var.enable_custom_domain]

  variables {
    enable_custom_domain = true
    domain_name          = "api.example.com"
    certificate_arn      = ""
  }
}
