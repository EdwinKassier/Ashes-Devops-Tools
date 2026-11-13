# MANDATORY (overridable set): deny any plan that destroys (delete or replace)
# a stateful or control-plane resource: data stores, encryption keys, log and
# audit storage, secrets, accounts/projects/folders, networks, organisation
# policies, backup vaults and locks, artefact registries and DNS zones. Losing
# a KMS key orphans every ciphertext; losing a log bucket breaks the audit
# trail; replacing a StackSet instance removes the AWS Config recorders
# org-wide. The set is overridable: the security team overrides an intended
# destroy on the run.
#
# It also denies an in-place update that turns a deletion-protection switch
# off, on any resource type: that is the first step of a two-run destroy, and
# the second run may delete a type that is not on the list.
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
	# Deleting the containment tag binding also lifts the tag-scoped deny.
	"google_tags_tag_binding",
	"google_tags_location_tag_binding",
	# Network: destroying the accepter deletes the spoke's TGW attachment.
	"aws_ec2_transit_gateway_vpc_attachment",
	"aws_ec2_transit_gateway_vpc_attachment_accepter",
	# Backups and immutability: deleting a vault or its lock removes the
	# recovery points or their lock; deleting an Object Lock configuration
	# lifts WORM on new objects.
	"aws_backup_vault",
	"aws_backup_vault_lock_configuration",
	"aws_s3_bucket_object_lock_configuration",
	"aws_efs_file_system",
	# Data and artefact stores.
	"google_bigquery_dataset",
	"aws_ecr_repository",
	"google_artifact_registry_repository",
	# DNS zones: a delete and re-create changes the delegated name servers.
	"aws_route53_zone",
	"google_dns_managed_zone",
	# Clusters and databases: a delete loses the data (GKE: the workloads and
	# their persistent volumes).
	"google_container_cluster",
	"google_spanner_instance",
	"google_spanner_database",
	"google_bigtable_instance",
	"google_filestore_instance",
	"google_sql_database",
	"aws_rds_global_cluster",
	"aws_elasticache_replication_group",
	"aws_elasticache_cluster",
	# Backup plans: a delete stops every future recovery point it schedules.
	"aws_backup_plan",
	"aws_backup_selection",
}

# Deletion-protection switches and their protected value, by attribute name in
# the provider schemas (hashicorp/aws 6.x, hashicorp/google 8.x; checked with
# `terraform providers schema -json` on 2026-11-13). Matched on every resource
# type that has the attribute. Examples:
#   deletion_protection             aws_rds_cluster, aws_rds_global_cluster,
#                                   aws_db_instance, aws_docdb_cluster,
#                                   aws_neptune_cluster, aws_eks_cluster,
#                                   google_container_cluster,
#                                   google_sql_database_instance,
#                                   google_spanner_database,
#                                   google_bigtable_instance, google_folder,
#                                   google_secret_manager_secret,
#                                   google_cloud_run_v2_service and _job
#   deletion_protection_enabled     aws_dynamodb_table, aws_cloudwatch_log_group,
#                                   aws_dsql_cluster, google_filestore_instance,
#                                   google_redis_cluster
#   enable_deletion_protection      aws_lb, aws_alb, google_workbench_instance
#   delete_protection               aws_networkfirewall_firewall
#   termination_protection_enabled  aws_cloudtrail_event_data_store
#   enable_drop_protection          google_spanner_database
#   deletion_policy = "PREVENT"     google 8.x resources (google_project, ...)
#   deletion_protection = "ACTIVE"  aws_cognito_user_pool (a string)
#   deletion_protection = "PROTECTED"         google_bigtable_table (a string)
#   delete_protection_state = "DELETE_PROTECTION_ENABLED"  google_firestore_database
# aws_elasticache_* and aws_backup_* have no such switch; the delete rule
# above covers them.
protection_on(attr, value) if {
	attr in {
		"deletion_protection",
		"deletion_protection_enabled",
		"enable_deletion_protection",
		"delete_protection",
		"termination_protection_enabled",
		"enable_drop_protection",
	}
	value == true
}

protection_on("deletion_policy", "PREVENT")

protection_on("deletion_protection", "ACTIVE")

protection_on("deletion_protection", "PROTECTED")

protection_on("delete_protection_state", "DELETE_PROTECTION_ENABLED")

# The planned value no longer protects: absent, null or any other value. The
# plan JSON leaves an unknown value out of `after` (after_unknown marks it), so
# an unknown value also counts as off: it cannot be checked.
turned_off contains [rc, attr] if {
	some rc in lib.managed
	"update" in rc.change.actions
	is_object(rc.change.before)
	some attr, before in rc.change.before
	protection_on(attr, before)
	object.get(object.get(rc.change, "after", {}), attr, null) != before
}

# google_sql_database_instance keeps a second switch in settings[0].
turned_off contains [rc, "settings.deletion_protection_enabled"] if {
	some rc in lib.managed
	rc.type == "google_sql_database_instance"
	"update" in rc.change.actions
	some i, s in object.get(rc.change.before, "settings", [])
	s.deletion_protection_enabled == true
	after_settings := object.get(object.get(rc.change, "after", {}), "settings", [])
	not after_settings[i].deletion_protection_enabled == true
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

deny contains msg if {
	some [rc, attr] in turned_off
	msg := sprintf("%s: plan turns off %s on %s; the security team must override this run if it is intended", [rc.address, attr, rc.type])
}
