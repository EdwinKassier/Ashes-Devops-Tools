# S3 public-access guardrails.
#   deny (MANDATORY):
#     - canned ACLs that grant public or any-authenticated-user access
#       (aws_s3_bucket_acl.acl, legacy aws_s3_bucket.acl)
#     - an aws_s3_bucket_public_access_block / aws_s3_account_public_access_block
#       with any of its four switches turned off
#   warn (ADVISORY):
#     - a NEW aws_s3_bucket whose module instance does not also create an
#       aws_s3_bucket_public_access_block (the bucket id is unknown at plan
#       time, so the pairing is by module address and count). An account-level
#       public access block created in the same plan satisfies it.
package terraform.policies.aws_s3_public_access

import rego.v1

import data.terraform.lib

public_acls := {"public-read", "public-read-write", "authenticated-read"}

pab_switches := {"block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"}

pab_types := {"aws_s3_bucket_public_access_block", "aws_s3_account_public_access_block"}

deny contains msg if {
	some t in {"aws_s3_bucket_acl", "aws_s3_bucket"}
	some rc in lib.written_of_type(t)
	lib.after(rc, "acl") in public_acls
	msg := sprintf("%s: public canned ACL %q is not allowed", [rc.address, lib.after(rc, "acl")])
}

deny contains msg if {
	some t in pab_types
	some rc in lib.written_of_type(t)
	some switch in pab_switches
	lib.known_and_not(rc, switch, true)
	msg := sprintf("%s: %s must be true", [rc.address, switch])
}

module_of(rc) := object.get(rc, "module_address", "")

new_buckets_in(mod) := count([rc |
	some rc in lib.managed
	rc.type == "aws_s3_bucket"
	lib.creates(rc)
	module_of(rc) == mod
])

new_pabs_in(mod) := count([rc |
	some rc in lib.managed
	rc.type == "aws_s3_bucket_public_access_block"
	lib.creates(rc)
	module_of(rc) == mod
])

account_pab_in_plan if {
	some rc in lib.managed
	rc.type == "aws_s3_account_public_access_block"
	not lib.deletes(rc)
}

warn contains msg if {
	not account_pab_in_plan
	some rc in lib.managed
	rc.type == "aws_s3_bucket"
	lib.creates(rc)
	new_pabs_in(module_of(rc)) < new_buckets_in(module_of(rc))
	msg := sprintf("%s: new bucket without a matching aws_s3_bucket_public_access_block in the same module", [rc.address])
}
