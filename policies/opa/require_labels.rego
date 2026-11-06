# ADVISORY: labellable GCP resources and taggable AWS resources carry
# ownership/cost metadata, so billing export, Cost Explorer and asset
# inventory queries can attribute them.
#   - GCP: at least one label (provider-level default_labels show up in
#     effective_labels, which is also accepted).
#   - AWS: at least one tag in tags_all (includes provider default_tags).
package terraform.policies.require_labels

import rego.v1

import data.terraform.lib

gcp_labelled_types := {
	"google_storage_bucket",
	"google_kms_crypto_key",
	"google_pubsub_topic",
	"google_bigquery_dataset",
	"google_compute_instance",
	"google_sql_database_instance",
	"google_cloud_run_v2_service",
	"google_secret_manager_secret",
	"google_artifact_registry_repository",
	"google_project",
}

aws_tagged_types := {
	"aws_s3_bucket",
	"aws_kms_key",
	"aws_vpc",
	"aws_instance",
	"aws_db_instance",
	"aws_rds_cluster",
	"aws_lb",
	"aws_ecs_service",
	"aws_lambda_function",
	"aws_iam_role",
	"aws_cloudwatch_log_group",
	"aws_secretsmanager_secret",
}

non_empty(obj) if {
	is_object(obj)
	count(obj) > 0
}

has_any(rc, attrs) if {
	some attr in attrs
	non_empty(lib.after(rc, attr))
}

# A computed (unknown) label/tag map is given the benefit of the doubt.
has_any(rc, attrs) if {
	some attr in attrs
	lib.unknown(rc, attr)
}

deny contains msg if {
	some t in gcp_labelled_types
	some rc in lib.written_of_type(t)
	not has_any(rc, ["labels", "effective_labels"])
	msg := sprintf("%s: must set at least one label", [rc.address])
}

deny contains msg if {
	some t in aws_tagged_types
	some rc in lib.written_of_type(t)
	not has_any(rc, ["tags", "tags_all"])
	msg := sprintf("%s: must carry at least one tag (tags or provider default_tags)", [rc.address])
}
