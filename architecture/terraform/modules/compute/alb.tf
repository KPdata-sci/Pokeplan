# One public ALB. Every request is signed in through OIDC at the load balancer
# before it reaches Metabase or Dagster. WAF sits in front with AWS managed rules.

resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
}

resource "aws_lb_target_group" "this" {
  for_each    = toset(["metabase", "dagster"])
  name        = "${var.name}-${each.key}"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path    = each.key == "metabase" ? "/api/health" : "/server_info"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "app" {
  for_each     = { metabase = 10, dagster = 20 }
  listener_arn = aws_lb_listener.https.arn
  priority     = each.value

  condition {
    host_header {
      values = ["${each.key}.${var.domain}"]
    }
  }

  action {
    type  = "authenticate-oidc"
    order = 1
    authenticate_oidc {
      issuer                     = var.oidc.issuer
      authorization_endpoint     = var.oidc.authorization_endpoint
      token_endpoint             = var.oidc.token_endpoint
      user_info_endpoint         = var.oidc.user_info_endpoint
      client_id                  = var.oidc.client_id
      client_secret              = var.oidc.client_secret
      on_unauthenticated_request = "authenticate"
    }
  }

  action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}

resource "aws_wafv2_web_acl" "this" {
  name  = var.name
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = {
      AWSManagedRulesAmazonIpReputationList = 1
      AWSManagedRulesCommonRuleSet          = 2
      AWSManagedRulesKnownBadInputsRuleSet  = 3
    }
    content {
      name     = rule.key
      priority = rule.value
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.key
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = rule.key
      }
    }
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 10
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "rate-limit-per-ip"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = var.name
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
