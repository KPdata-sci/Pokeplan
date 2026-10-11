# ---------- Network Firewall (prod) ----------
# Strict rule order + "drop established" default: a TLS or HTTP connection is
# allowed only when its SNI / Host header is on the allowlist.

resource "aws_networkfirewall_rule_group" "egress_allowlist" {
  count    = var.enable_network_firewall ? 1 : 0
  name     = "${var.name}-egress-allowlist"
  type     = "STATEFUL"
  capacity = 100

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [var.cidr]
        }
      }
    }
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets              = var.egress_domains
      }
    }
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "this" {
  count = var.enable_network_firewall ? 1 : 0
  name  = "${var.name}-egress"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_default_actions           = ["aws:drop_established", "aws:alert_established"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }
    stateful_rule_group_reference {
      priority     = 100
      resource_arn = aws_networkfirewall_rule_group.egress_allowlist[0].arn
    }
  }
}

resource "aws_networkfirewall_firewall" "this" {
  count               = var.enable_network_firewall ? 1 : 0
  name                = var.name
  vpc_id              = aws_vpc.this.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this[0].arn
  delete_protection   = true

  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }

  lifecycle {
    precondition {
      condition     = !var.single_nat_gateway
      error_message = "Network Firewall routing here assumes one NAT gateway per AZ; set single_nat_gateway = false."
    }
  }
}

resource "aws_cloudwatch_log_group" "firewall_alerts" {
  count             = var.enable_network_firewall ? 1 : 0
  name              = "/network-firewall/${var.name}/alerts"
  retention_in_days = var.flow_log_retention_days
}

resource "aws_networkfirewall_logging_configuration" "this" {
  count        = var.enable_network_firewall ? 1 : 0
  firewall_arn = aws_networkfirewall_firewall.this[0].arn

  logging_configuration {
    log_destination_config {
      log_type             = "ALERT"
      log_destination_type = "CloudWatchLogs"
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_alerts[0].name
      }
    }
  }
}

# ---------- Route 53 Resolver DNS Firewall (learning) ----------
# Much cheaper than Network Firewall. It only filters DNS lookups, so a task that
# connects straight to an IP address gets past it; fine for learning, not for prod.

locals {
  dns_firewall = !var.enable_network_firewall && var.enable_dns_firewall ? 1 : 0
}

resource "aws_route53_resolver_firewall_domain_list" "allowed" {
  count   = local.dns_firewall
  name    = "${var.name}-allowed"
  domains = var.dns_allowed_domains
}

resource "aws_route53_resolver_firewall_domain_list" "everything" {
  count   = local.dns_firewall
  name    = "${var.name}-everything"
  domains = ["*."]
}

resource "aws_route53_resolver_firewall_rule_group" "this" {
  count = local.dns_firewall
  name  = "${var.name}-egress"
}

resource "aws_route53_resolver_firewall_rule" "allow" {
  count                   = local.dns_firewall
  name                    = "allow-listed"
  action                  = "ALLOW"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.allowed[0].id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this[0].id
  priority                = 100
}

resource "aws_route53_resolver_firewall_rule" "block" {
  count                   = local.dns_firewall
  name                    = "block-rest"
  action                  = "BLOCK"
  block_response          = "NXDOMAIN"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.everything[0].id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this[0].id
  priority                = 200
}

resource "aws_route53_resolver_firewall_rule_group_association" "this" {
  count                  = local.dns_firewall
  name                   = var.name
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.this[0].id
  vpc_id                 = aws_vpc.this.id
  priority               = 101
}
