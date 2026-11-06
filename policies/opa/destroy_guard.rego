# ADVISORY: flag any plan that destroys (delete or replace) a protected,
# hard-to-recreate control-plane resource: encryption keys, log/audit
# storage and organisation policies. Losing a KMS key orphans every
# ciphertext; losing a log bucket breaks the audit trail; deleting an org
# policy silently widens the guardrail perimeter. Review and override.
package terraform.policies.destroy_guard

import rego.v1

import data.terraform.lib

protected_types := {
	# Keys
	"google_kms_crypto_key",
	"google_kms_key_ring",
	"aws_kms_key",
	"aws_kms_replica_key",
	# Log / audit storage
	"google_logging_project_bucket_config",
	"google_logging_folder_bucket_config",
	"google_logging_organization_bucket_config",
	"google_logging_organization_sink",
	"google_logging_folder_sink",
	"aws_cloudtrail",
	"aws_cloudtrail_event_data_store",
	# Organisation policy
	"google_org_policy_policy",
	"google_organization_policy",
	"google_folder_organization_policy",
	"google_project_organization_policy",
	"google_access_context_manager_service_perimeter",
	"aws_organizations_policy",
	"aws_organizations_policy_attachment",
	"aws_organizations_organization",
}

# Storage buckets whose name marks them as log / audit archives.
log_bucket(rc) if {
	rc.type in {"aws_s3_bucket", "google_storage_bucket"}
	name := object.get(rc.change.before, "bucket", object.get(rc.change.before, "name", ""))
	regex.match(`(?i)(^|[-_.])(logs?|audit|cloudtrail|log-archive)([-_.]|$)`, name)
}

action_verb(rc) := "replaces" if lib.creates(rc)

action_verb(rc) := "destroys" if not lib.creates(rc)

protected(rc) if rc.type in protected_types

protected(rc) if log_bucket(rc)

deny contains msg if {
	some rc in lib.managed
	lib.deletes(rc)
	protected(rc)
	verb := action_verb(rc)
	msg := sprintf("%s: plan %s a protected %s; confirm this is intended", [rc.address, verb, rc.type])
}
