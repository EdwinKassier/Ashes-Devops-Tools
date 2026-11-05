# Elastic Load Balancing primitive for the AWS landing zone — the AWS parity
# counterpart to the GCP internal-lb module.
#
# Composes the three building blocks of an ELB v2 load balancer:
#   - aws_lb                : the load balancer itself (application OR network,
#                             internet-facing OR internal)
#   - aws_lb_target_group   : one per entry in var.target_groups (for_each)
#   - aws_lb_listener       : one per entry in var.listeners (for_each); the
#                             default action forwards to a named target group,
#                             returns a fixed response, or redirects to HTTPS
#   - aws_lb_listener_rule  : one per entry in var.listener_rules — host/path
#                             routing to a target group (shared ALB pattern)
#
# An optional security group (var.create_security_group) is created for ALBs;
# its id is merged with any caller-supplied var.security_group_ids. Access
# logging to S3 is opt-in via var.access_logs.

locals {
  # Only application load balancers use HTTP-header hardening; NLBs reject the
  # argument, so it is left null (provider default) for network type.
  is_application = var.load_balancer_type == "application"

  # Security groups attached to the load balancer: the caller-supplied ids plus
  # the module-created one (if any). Passing an empty list would still attach a
  # provider-selected default, so collapse to null when nothing is configured.
  security_group_ids = concat(
    var.security_group_ids,
    var.create_security_group ? [aws_security_group.this[0].id] : [],
  )
}

# -----------------------------------------------------------------------------
# SECURITY GROUP (ALB only, opt-in)
# -----------------------------------------------------------------------------

resource "aws_security_group" "this" {
  # checkov:skip=CKV2_AWS_5:This SG IS attached to aws_lb.this via local.security_group_ids (security_groups = [...aws_security_group.this[0].id]). Checkov's graph check cannot resolve the count + local + ternary indirection between the SG and the LB, so it reports the SG as unattached — a false positive.
  count = var.create_security_group ? 1 : 0

  name        = "${var.name}-lb"
  description = "Managed security group for the ${var.name} load balancer."
  vpc_id      = var.vpc_id

  # Egress lets the LB reach its targets on any port, limited to
  # var.egress_cidr_blocks (narrow it to the VPC CIDR when targets are in-VPC);
  # ingress is left to the caller (add rules via the exported security_group_id)
  # so this module does not silently expose the LB to the internet.
  egress {
    description = "Allow outbound to targets."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_blocks #tfsec:ignore:aws-ec2-no-public-egress-sgr -- LB must reach targets; ingress is caller-controlled
  }

  tags = merge(var.tags, { Name = "${var.name}-lb" })
}

# -----------------------------------------------------------------------------
# LOAD BALANCER
# -----------------------------------------------------------------------------

resource "aws_lb" "this" {
  # checkov:skip=CKV_AWS_91:Access logging is opt-in via var.access_logs (the caller supplies the S3 bucket + prefix). The dynamic access_logs block enables it when configured; a landing-zone LB primitive cannot mandate a bucket it does not own.
  name               = var.name
  load_balancer_type = var.load_balancer_type
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = length(local.security_group_ids) > 0 ? local.security_group_ids : null

  # Header hardening is an ALB-only concept.
  drop_invalid_header_fields = local.is_application ? var.drop_invalid_header_fields : null

  enable_deletion_protection = var.enable_deletion_protection

  # Always on for ALBs; NLBs default it off, which concentrates traffic on the
  # targets in the client's AZ and fails badly when one AZ is unhealthy.
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  dynamic "access_logs" {
    for_each = var.access_logs != null ? [var.access_logs] : []
    content {
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
      enabled = access_logs.value.enabled
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

# -----------------------------------------------------------------------------
# TARGET GROUPS
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = each.value.name
  vpc_id      = var.vpc_id
  port        = each.value.port
  protocol    = each.value.protocol
  target_type = each.value.target_type

  dynamic "health_check" {
    for_each = each.value.health_check != null ? [each.value.health_check] : []
    content {
      enabled             = health_check.value.enabled
      path                = health_check.value.path
      port                = health_check.value.port
      protocol            = health_check.value.protocol
      healthy_threshold   = health_check.value.healthy_threshold
      unhealthy_threshold = health_check.value.unhealthy_threshold
      interval            = health_check.value.interval
      timeout             = health_check.value.timeout
      matcher             = health_check.value.matcher
    }
  }

  tags = merge(var.tags, { Name = each.value.name })
}

# -----------------------------------------------------------------------------
# LISTENERS
# -----------------------------------------------------------------------------

resource "aws_lb_listener" "this" {
  # checkov:skip=CKV_AWS_2:The module intentionally supports both HTTP and HTTPS listeners — HTTP is needed for NLB (TCP/UDP) and for HTTP->HTTPS redirect listeners. HTTPS is fully supported per listener via certificate_arn + ssl_policy; the protocol is a caller choice, not a module default.
  # checkov:skip=CKV_AWS_103:ssl_policy defaults to ELBSecurityPolicy-TLS13-1-2-2021-06 (TLS 1.3/1.2) in the listeners variable, so TLS-terminating listeners are >= TLS 1.2 by default. Checkov cannot resolve the for_each optional() variable default and reads it as unset — verified by the secure default in variables.tf.
  for_each = var.listeners

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol

  # certificate_arn / ssl_policy apply only to TLS-terminating listeners
  # (HTTPS on ALB, TLS on NLB); they are null for plain HTTP/TCP.
  certificate_arn = each.value.certificate_arn
  ssl_policy      = each.value.certificate_arn != null ? each.value.ssl_policy : null

  # Default action: forward to a target group (single-service LB), a fixed
  # response (shared LB whose services are routed by listener_rules), or an
  # HTTP -> HTTPS redirect.
  default_action {
    type             = each.value.default_action == "redirect-https" ? "redirect" : each.value.default_action
    target_group_arn = each.value.default_action == "forward" ? aws_lb_target_group.this[each.value.target_group_key].arn : null

    dynamic "fixed_response" {
      for_each = each.value.default_action == "fixed-response" ? [each.value.fixed_response] : []
      content {
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
        status_code  = fixed_response.value.status_code
      }
    }

    dynamic "redirect" {
      for_each = each.value.default_action == "redirect-https" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# LISTENER RULES — host/path routing to target groups (shared ALB)
# -----------------------------------------------------------------------------

resource "aws_lb_listener_rule" "this" {
  for_each = var.listener_rules

  listener_arn = aws_lb_listener.this[each.value.listener_key].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group_key].arn
  }

  dynamic "condition" {
    for_each = length(each.value.host_headers) > 0 ? [each.value.host_headers] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.path_patterns) > 0 ? [each.value.path_patterns] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  tags = var.tags
}
