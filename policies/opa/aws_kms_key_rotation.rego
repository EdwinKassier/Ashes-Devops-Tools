# MANDATORY: symmetric customer-managed KMS keys must rotate
# (enable_key_rotation = true). Asymmetric and HMAC keys cannot rotate in
# AWS and are exempt. An unknown enable_key_rotation is a violation; an
# unknown customer_master_key_spec counts as symmetric.
package terraform.policies.aws_kms_key_rotation

import rego.v1

import data.terraform.lib

symmetric(rc) if object.get(rc.change.after, "customer_master_key_spec", "SYMMETRIC_DEFAULT") == "SYMMETRIC_DEFAULT"

deny contains msg if {
	some rc in lib.written_of_type("aws_kms_key")
	symmetric(rc)
	lib.unknown_or_not(rc, "enable_key_rotation", true)
	msg := sprintf("%s: enable_key_rotation must be true%s", [rc.address, lib.unknown_hint])
}
