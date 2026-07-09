# Per-workload edge security for the SRA landing zone.
#
# Optional, workload-owned counterpart to the org-wide Firewall Manager guardrail
# (module aws/firewall-manager-org). Where FMS enforces a baseline WAF policy
# across every account, this module provisions the edge stack a single workload
# fronts its app with: a CloudFront distribution, a CloudFront-scoped WAFv2 Web
# ACL, an optional ACM certificate, optional Shield Advanced enrollment, and
# optional WAF logging.
#
# CloudFront is a global service whose WAF and ACM dependencies must live in
# us-east-1 regardless of where the workload runs, so those resources use the
# aliased `aws.us_east_1` provider. Everything is count-gated on `enable_edge`
# so the module is inert until a workload opts in.

# CloudFront-scoped Web ACL. Must be created in us-east-1.
resource "aws_wafv2_web_acl" "cloudfront" {
  # checkov:skip=CKV2_AWS_31:WAF logging is opt-in via var.log_destination_arn,
  #   which wires aws_wafv2_web_acl_logging_configuration.this to a caller-owned
  #   destination. A logging config is intentionally not forced on every ACL (same
  #   per-workload rationale as CKV_AWS_86 on the distribution); Checkov's graph
  #   check cannot resolve the conditional logging resource.
  count    = var.enable_edge ? 1 : 0
  provider = aws.us_east_1
  name     = "${var.name_prefix}-cf-acl"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-common"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }

  # KnownBadInputs carries the Log4JRCE rule (CVE-2021-44228 / Log4Shell) plus
  # other known-exploit signatures. Kept as a distinct managed rule group so the
  # Log4Shell protection is explicit rather than assumed to be inside Common.
  rule {
    name     = "aws-known-bad-inputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-cf-acl"
    sampled_requests_enabled   = true
  }
}

# ACM certificate for the custom domain. CloudFront requires certs in us-east-1.
resource "aws_acm_certificate" "this" {
  count             = var.enable_edge && var.domain_name != "" ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "this" {
  # checkov:skip=CKV_AWS_86:Access logging is a per-workload choice wired via the
  #   caller's own logging bucket; WAF request logging is offered here via
  #   var.log_destination_arn. A baseline logging_config is intentionally not
  #   forced on every distribution.
  # checkov:skip=CKV_AWS_310:Origin failover requires a second origin + origin_group,
  #   which is workload-topology-specific. This module ships a single-origin edge;
  #   callers add failover when they run redundant origins.
  # checkov:skip=CKV_AWS_305:The default root object is application-specific
  #   (e.g. index.html) and is left to the workload rather than defaulted here.
  # checkov:skip=CKV_AWS_374:geo_restriction is deliberately "none" — this is a
  #   generic edge; geo-blocking is a per-workload policy decision, not a baseline.
  # checkov:skip=CKV2_AWS_42:A custom ACM certificate IS used when var.domain_name is
  #   set (acm_certificate_arn + sni-only below). The default *.cloudfront.net cert is
  #   only used when no domain is supplied; Checkov cannot resolve this conditional and
  #   flags the default-cert branch. Same conditional as CKV_AWS_174 on viewer_certificate.
  # checkov:skip=CKV2_AWS_32:A response-headers policy is application-specific (CSP, HSTS,
  #   and permissions tuned to the workload's app) and is left to the caller, consistent
  #   with CKV_AWS_305 (default root object). This module ships a generic single-origin edge.
  # checkov:skip=CKV2_AWS_47:Log4Shell (CVE-2021-44228) protection IS present on the attached
  #   web_acl_id — aws_wafv2_web_acl.cloudfront attaches AWSManagedRulesKnownBadInputsRuleSet
  #   (which carries the Log4JRCE rule) at priority 2. Checkov's AMR graph check only
  #   recognizes a specific managed-rule-group shape and does not resolve this association.
  count      = var.enable_edge ? 1 : 0
  enabled    = true
  web_acl_id = aws_wafv2_web_acl.cloudfront[0].arn

  origin {
    domain_name = var.origin_domain_name
    origin_id   = "default"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "default"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = var.cache_policy_id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # checkov:skip=CKV_AWS_174:When a custom domain is set, minimum_protocol_version
    #   is pinned to TLSv1.2_2021. When domain_name is empty the *cloudfront.net
    #   default certificate is used, whose minimum protocol is fixed by AWS and not
    #   configurable; Checkov cannot resolve this conditional and flags the default-cert
    #   branch. Custom-domain deployments (the production path) satisfy the check.
    cloudfront_default_certificate = var.domain_name == "" ? true : null
    acm_certificate_arn            = var.domain_name != "" ? aws_acm_certificate.this[0].arn : null
    ssl_support_method             = var.domain_name != "" ? "sni-only" : null
    minimum_protocol_version       = var.domain_name != "" ? "TLSv1.2_2021" : null
  }
}

# Shield Advanced enrollment for the distribution. Cost-gated.
resource "aws_shield_protection" "this" {
  count        = var.enable_edge && var.enable_shield ? 1 : 0
  name         = "${var.name_prefix}-cf"
  resource_arn = aws_cloudfront_distribution.this[0].arn
}

# WAF logging to the caller-supplied destination. Created in us-east-1 to match
# the Web ACL scope.
resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count                   = var.enable_edge && var.log_destination_arn != "" ? 1 : 0
  provider                = aws.us_east_1
  resource_arn            = aws_wafv2_web_acl.cloudfront[0].arn
  log_destination_configs = [var.log_destination_arn]
}
