# Plan-assertion tests for the aws-shared-services stage.
#
# A single mock provider (the stage has one default provider, no aliases). The
# stage just wires two gated children through to its outputs, so the tests prove
# the OUTPUT WIRING (child output -> stage output edges) in both the enabled and
# disabled states.
#
# Enabled state: the children's ca_arn / secret_arns are computed (unknown) under
# mock, so we override_module both children with KNOWN values and assert the
# stage outputs surface exactly those — a concrete, non-vacuous wiring proof.
#
# Disabled state: with both gates false the children create nothing, so ca_arn
# must be null and secret_arns must be the empty map (no overrides — the real
# child logic runs).

mock_provider "aws" {}

run "composes_shared_services_when_enabled" {
  command = apply

  variables {
    enable_private_ca       = true
    ca_common_name          = "ashes-internal-ca"
    share_ca_org            = true
    org_arn                 = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    enable_secrets_baseline = true
    org_id                  = "o-abc1234567"
    secrets = {
      "app/db-password" = {}
    }
  }

  # Known CA arn so the ca_arn wiring assertion is non-vacuous.
  override_module {
    target = module.private_ca
    outputs = {
      ca_arn             = "arn:aws:acm-pca:eu-west-2:222222222222:certificate-authority/abcd1234-0000-0000-0000-000000000000"
      resource_share_arn = "arn:aws:ram:eu-west-2:222222222222:resource-share/ffff0000"
    }
  }

  # Known secret arns map so the secret_arns wiring assertion is non-vacuous.
  override_module {
    target = module.secrets_baseline
    outputs = {
      secret_arns = {
        "app/db-password" = "arn:aws:secretsmanager:eu-west-2:222222222222:secret:app/db-password-AbCdEf"
      }
    }
  }

  # ca_arn output surfaces module.private_ca.ca_arn.
  assert {
    condition     = output.ca_arn == "arn:aws:acm-pca:eu-west-2:222222222222:certificate-authority/abcd1234-0000-0000-0000-000000000000"
    error_message = "ca_arn output must surface module.private_ca.ca_arn when the CA is enabled"
  }

  # secret_arns output surfaces module.secrets_baseline.secret_arns.
  assert {
    condition     = output.secret_arns["app/db-password"] == "arn:aws:secretsmanager:eu-west-2:222222222222:secret:app/db-password-AbCdEf"
    error_message = "secret_arns output must surface module.secrets_baseline.secret_arns when the baseline is enabled"
  }
}

run "creates_nothing_when_disabled" {
  command = apply

  variables {
    enable_private_ca       = false
    enable_secrets_baseline = false
  }

  # No CA created -> the child's try(...) resolves to null and surfaces as null.
  assert {
    condition     = output.ca_arn == null
    error_message = "ca_arn must be null when the Private CA capability is disabled"
  }

  # No secrets created -> the child's map comprehension resolves to {}.
  assert {
    condition     = length(output.secret_arns) == 0
    error_message = "secret_arns must be empty when the Secrets baseline is disabled"
  }
}
