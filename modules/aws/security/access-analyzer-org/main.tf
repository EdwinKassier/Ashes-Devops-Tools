# Organization-scoped IAM Access Analyzer for the SRA landing zone.
#
# Creates organization analyzers:
#   * external — surfaces resources shared with principals outside the org.
#                One per enabled region: the unkeyed resource lives in the
#                provider's (home) region; external_extra adds the rest via the
#                resource-level `region` argument (aws provider >= 6.0), so no
#                provider aliases are needed.
#   * internal — (enable_internal_access_analyzer) ORGANIZATION_INTERNAL_ACCESS,
#                same home + per-region pattern.
#   * unused   — surfaces unused IAM access (roles, users, permissions) older
#                than unused_access_age days. Region-independent findings, so a
#                single analyzer in the home region.
#
# Both analyzers are ORGANIZATION scoped, so this module is applied with the
# IAM Access Analyzer delegated-administrator provider. Delegated-admin
# registration for access-analyzer.amazonaws.com is performed SEPARATELY (in the
# security-delegated-admin module / stage), NOT here — Access Analyzer has no
# dedicated delegated-admin resource of its own.

resource "aws_accessanalyzer_analyzer" "external" {
  analyzer_name = var.external_analyzer_name
  type          = "ORGANIZATION"
  tags          = var.tags
}

locals {
  extra_regions = setsubtract(toset(var.regions), toset([var.home_region]))
}

# External-access analyzer in every other enabled region (the unkeyed
# `external` analyzer above covers the home region and keeps its state address).
resource "aws_accessanalyzer_analyzer" "external_extra" {
  for_each = local.extra_regions

  region        = each.key
  analyzer_name = var.external_analyzer_name
  type          = "ORGANIZATION"
  tags          = var.tags
}

# Internal-access analyzer (who inside the org can reach critical resources).
resource "aws_accessanalyzer_analyzer" "internal" {
  count = var.enable_internal_access_analyzer ? 1 : 0

  analyzer_name = var.internal_analyzer_name
  type          = "ORGANIZATION_INTERNAL_ACCESS"

  configuration {
    internal_access {
      analysis_rule {
        inclusion {
          resource_types = length(var.internal_access_resource_types) > 0 ? var.internal_access_resource_types : null
        }
      }
    }
  }

  tags = var.tags
}

resource "aws_accessanalyzer_analyzer" "internal_extra" {
  for_each = var.enable_internal_access_analyzer ? local.extra_regions : toset([])

  region        = each.key
  analyzer_name = var.internal_analyzer_name
  type          = "ORGANIZATION_INTERNAL_ACCESS"

  configuration {
    internal_access {
      analysis_rule {
        inclusion {
          resource_types = length(var.internal_access_resource_types) > 0 ? var.internal_access_resource_types : null
        }
      }
    }
  }

  tags = var.tags
}

resource "aws_accessanalyzer_analyzer" "unused" {
  analyzer_name = var.unused_analyzer_name
  type          = "ORGANIZATION_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = var.unused_access_age
    }
  }

  tags = var.tags
}
