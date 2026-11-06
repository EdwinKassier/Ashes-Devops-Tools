# MANDATORY: Cloud Storage buckets must be private by construction.
#   - uniform_bucket_level_access = true (no per-object ACLs)
#   - public_access_prevention    = "enforced"
# Public IAM grants on buckets are covered by gcp_iam_no_public_members.
package terraform.policies.gcs_no_public_buckets

import rego.v1

import data.terraform.lib

required := {
	"public_access_prevention": "enforced",
	"uniform_bucket_level_access": true,
}

deny contains msg if {
	some rc in lib.written_of_type("google_storage_bucket")
	some attr, want in required
	lib.known_and_not(rc, attr, want)
	msg := sprintf("%s: %s must be %v", [rc.address, attr, want])
}
