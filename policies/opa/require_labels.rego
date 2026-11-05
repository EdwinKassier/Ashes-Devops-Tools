# Advisory: labellable GCP resources must carry at least one label, so cost
# allocation and ownership queries (billing export, asset inventory) work.
package terraform.policies.require_labels

import rego.v1

import input.plan as plan

labelled_types := {
	"google_storage_bucket",
	"google_kms_crypto_key",
	"google_pubsub_topic",
	"google_bigquery_dataset",
}

writes(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}

has_labels(after) if {
	is_object(after.labels)
	count(after.labels) > 0
}

deny contains msg if {
	some rc in plan.resource_changes
	rc.type in labelled_types
	writes(rc)
	not has_labels(rc.change.after)
	msg := sprintf("%s: must set at least one label", [rc.address])
}
