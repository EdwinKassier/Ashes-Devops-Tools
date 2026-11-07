# Plan assertions for the governance/tags module: verify tag keys are planned under
# the caller-supplied org with the expected short names.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  org_id = "123456789"
  tags = {
    environment = {
      values      = ["dev", "prod"]
      description = "Deployment environment tier"
    }
  }
}

run "tag_key_and_values_wired" {
  command = plan

  assert {
    condition     = google_tags_tag_key.keys["environment"].short_name == "environment"
    error_message = "Tag key short_name must match the caller-supplied key."
  }

  assert {
    condition     = google_tags_tag_key.keys["environment"].parent == "organizations/${var.org_id}"
    error_message = "Tag key parent must reference the caller-supplied org_id."
  }

  assert {
    condition     = length(google_tags_tag_value.values) == 2
    error_message = "One tag value must be planned per supplied value (dev, prod)."
  }
}

# google_tags_tag_key/value .name is the bare numeric ID. Consumers (tag value
# parent, tag bindings, IAM deny matchTagId) need the namespaced
# tagKeys/<n> / tagValues/<n> form, so the module builds it.
run "outputs_and_parent_are_namespaced" {
  command = plan

  override_resource {
    target          = google_tags_tag_key.keys
    override_during = plan
    values = {
      name = "111"
    }
  }

  override_resource {
    target          = google_tags_tag_value.values
    override_during = plan
    values = {
      name = "222"
    }
  }

  assert {
    condition     = google_tags_tag_value.values["environment-dev"].parent == "tagKeys/111"
    error_message = "a tag value's parent must be tagKeys/<n>, not the bare numeric name."
  }

  assert {
    condition     = output.tag_keys["environment"] == "tagKeys/111" && output.tag_values["environment-dev"] == "tagValues/222"
    error_message = "tag_keys / tag_values must expose the namespaced IDs."
  }
}

