# Network Access Analyzer scope: encodes a network-segmentation INTENT that AWS
# can continuously validate — e.g. "no path exists from the internet gateway to
# isolated instances". The scope declares which source -> destination paths to
# match; a matched path in a later analysis is a segmentation violation.
#
# This module manages the SCOPE ONLY. Scope analyses
# (aws_ec2_network_insights_access_scope_analysis does NOT exist as a resource)
# are run out-of-band — via `aws ec2 start-network-insights-access-scope-analysis`,
# a scheduled job, or the console — against the scope id output here.
#
# Optional and OFF by default: set enable_network_access_analyzer = true to
# create the scope. Requires the AWS provider >= 6.43 (the
# aws_ec2_network_insights_access_scope resource); this module's floor of
# >= 6.46.0 covers that.

resource "aws_ec2_network_insights_access_scope" "this" {
  count = var.enable_network_access_analyzer ? 1 : 0

  dynamic "match_paths" {
    for_each = var.match_paths
    content {
      source {
        resource_statement {
          resource_types = match_paths.value.source_resource_types
        }
      }
      destination {
        resource_statement {
          resource_types = match_paths.value.destination_resource_types
        }
      }
    }
  }

  dynamic "exclude_paths" {
    for_each = var.exclude_paths
    content {
      source {
        resource_statement {
          resource_types = exclude_paths.value.source_resource_types
        }
      }
      destination {
        resource_statement {
          resource_types = exclude_paths.value.destination_resource_types
        }
      }
    }
  }
}
