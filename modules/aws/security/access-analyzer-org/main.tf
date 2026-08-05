# Organization-scoped IAM Access Analyzer for the SRA landing zone.
#
# Creates two organization analyzers:
#   * external — surfaces resources shared with principals outside the org.
#   * unused   — surfaces unused IAM access (roles, users, permissions) older
#                than unused_access_age days.
#
# Both analyzers are ORGANIZATION scoped, so this module is applied with the
# IAM Access Analyzer delegated-administrator provider. Delegated-admin
# registration for access-analyzer.amazonaws.com is performed SEPARATELY (in the
# security-delegated-admin module / stage), NOT here — Access Analyzer has no
# dedicated delegated-admin resource of its own.

resource "aws_accessanalyzer_analyzer" "external" {
  analyzer_name = var.external_analyzer_name
  type          = "ORGANIZATION"
}

resource "aws_accessanalyzer_analyzer" "unused" {
  analyzer_name = var.unused_analyzer_name
  type          = "ORGANIZATION_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = var.unused_access_age
    }
  }
}
