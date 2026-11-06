# MANDATORY: managed databases are private and encrypted at rest.
#   - google_sql_database_instance: settings.ip_configuration.ipv4_enabled = false
#     (no public IP; Cloud SQL is always encrypted at rest by Google)
#   - aws_db_instance:          storage_encrypted = true, publicly_accessible = false
#   - aws_rds_cluster:          storage_encrypted = true
#   - aws_rds_cluster_instance: publicly_accessible = false
# Cloud SQL defaults ipv4_enabled to true when ip_configuration is omitted,
# so an absent block is a violation.
package terraform.policies.database_private_encrypted

import rego.v1

import data.terraform.lib

sql_public_ip(rc) if {
	some settings in object.get(rc.change.after, "settings", [])
	ipcs := object.get(settings, "ip_configuration", [])
	count(ipcs) == 0
}

sql_public_ip(rc) if {
	some settings in object.get(rc.change.after, "settings", [])
	some ipc in object.get(settings, "ip_configuration", [])
	object.get(ipc, "ipv4_enabled", true) != false
}

deny contains msg if {
	some rc in lib.written_of_type("google_sql_database_instance")
	sql_public_ip(rc)
	msg := sprintf("%s: settings.ip_configuration.ipv4_enabled must be false (private IP only)", [rc.address])
}

encrypted_types := {"aws_db_instance", "aws_rds_cluster"}

private_types := {"aws_db_instance", "aws_rds_cluster_instance"}

deny contains msg if {
	some t in encrypted_types
	some rc in lib.written_of_type(t)
	lib.known_and_not(rc, "storage_encrypted", true)
	msg := sprintf("%s: storage_encrypted must be true", [rc.address])
}

deny contains msg if {
	some t in private_types
	some rc in lib.written_of_type(t)
	lib.after(rc, "publicly_accessible") == true
	msg := sprintf("%s: publicly_accessible must be false", [rc.address])
}
