package terraform.policies.require_labels_test

import rego.v1

import data.terraform.policies.require_labels as p

one(type, after, unknown) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": unknown},
}]}}

test_labelled_gcp_resource_passes if {
	count(p.deny) == 0 with input as one("google_storage_bucket", {"labels": {"env": "prod"}}, {})
}

test_default_labels_pass if {
	count(p.deny) == 0 with input as one("google_pubsub_topic", {"labels": null, "effective_labels": {"owner": "platform"}}, {})
}

test_unlabelled_gcp_resource_fails if {
	count(p.deny) == 1 with input as one("google_kms_crypto_key", {"labels": {}}, {})
}

test_tagged_aws_resource_passes if {
	count(p.deny) == 0 with input as one("aws_s3_bucket", {"tags": null, "tags_all": {"Owner": "platform"}}, {})
}

test_untagged_aws_resource_fails if {
	count(p.deny) == 1 with input as one("aws_kms_key", {"tags": null, "tags_all": {}}, {})
}

test_unknown_tags_pass if {
	count(p.deny) == 0 with input as one("aws_vpc", {}, {"tags_all": true})
}

test_untracked_type_ignored if {
	count(p.deny) == 0 with input as one("aws_route", {}, {})
}
