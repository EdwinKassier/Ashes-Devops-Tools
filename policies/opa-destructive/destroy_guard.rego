# MANDATORY (overridable set): deny any plan that destroys (delete or replace)
# a stateful or control-plane resource: data stores, encryption keys, log and
# audit storage, secrets, accounts/projects/folders, networks and
# organisation policies. Losing a KMS key orphans every ciphertext; losing a
# log bucket breaks the audit trail; replacing a StackSet instance removes the
# AWS Config recorders org-wide. The set is overridable: the security team
# overrides an intended destroy on the run.
package terraform.policies.destroy_guard

import rego.v1

import data.terraform.lib

protected_types := {
	# GCP stateful resources
	"google_sql_database_instance",
	"google_storage_bucket",
	"google_kms_crypto_key",
	"google_project",
	"google_folder",
	"google_compute_network",
	"google_logging_organization_sink",
	"google_logging_project_bucket_config",
	"google_secret_manager_secret",
	# AWS stateful resources
	"aws_s3_bucket",
	"aws_rds_cluster",
	"aws_db_instance",
	"aws_kms_key",
	"aws_organizations_account",
	"aws_dynamodb_table",
	"aws_vpc",
	"aws_cloudtrail",
	"aws_secretsmanager_secret",
	# Replacing it removes the recorders it deploys, org-wide.
	"aws_cloudformation_stack_set_instance",
	# Supabase
	"supabase_project",
	# Keys, log storage and organisation policy (control plane)
	"google_kms_key_ring",
	"aws_kms_replica_key",
	"google_logging_folder_bucket_config",
	"google_logging_organization_bucket_config",
	"google_logging_folder_sink",
	"aws_cloudtrail_event_data_store",
	"google_org_policy_policy",
	"google_organization_policy",
	"google_folder_organization_policy",
	"google_project_organization_policy",
	"google_access_context_manager_service_perimeter",
	"aws_organizations_policy",
	"aws_organizations_policy_attachment",
	"aws_organizations_organization",
	# Admin containment: deleting a deny policy, or the containment tag key or
	# value its conditions match, silently lifts the containment.
	"google_iam_deny_policy",
	"google_tags_tag_key",
	"google_tags_tag_value",
}

action_verb(rc) := "replaces" if lib.creates(rc)

action_verb(rc) := "destroys" if not lib.creates(rc)

deny contains msg if {
	some rc in lib.managed
	lib.deletes(rc)
	rc.type in protected_types
	verb := action_verb(rc)
	msg := sprintf("%s: plan %s a stateful %s; the security team must override this run if it is intended", [rc.address, verb, rc.type])
}
