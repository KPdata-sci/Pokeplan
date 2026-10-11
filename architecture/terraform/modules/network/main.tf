# Five subnet tiers per AZ (10.40.0.0/16):
#   public    10.40.0.0/24 ..   load balancer only
#   egress    10.40.5.0/24 ..   NAT gateways
#   app       10.40.10.0/24 ..  ECS tasks, Lambda
#   data      10.40.20.0/24 ..  RDS, no route out
#   firewall  10.40.30.0/28 ..  Network Firewall endpoints (prod only)
#
# Outbound path with the firewall on:  app -> firewall -> NAT -> internet gateway
# Return path:                         internet gateway -> NAT -> firewall -> app

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  az_index = { for i, az in local.azs : az => i }
  nat_azs  = var.single_nat_gateway ? { (local.azs[0]) = 0 } : local.az_index
  nat_for  = { for az in local.azs : az => var.single_nat_gateway ? local.azs[0] : az }
  firewall = var.enable_network_firewall ? local.az_index : {}

  firewall_endpoints = var.enable_network_firewall ? {
    for s in aws_networkfirewall_firewall.this[0].firewall_status[0].sync_states :
    s.availability_zone => s.attachment[0].endpoint_id
  } : {}
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

# Lock down the default security group so nothing can use it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

# ---------- subnets ----------

resource "aws_subnet" "public" {
  for_each          = local.az_index
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, each.value)
  tags              = { Name = "${var.name}-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "egress" {
  for_each          = local.az_index
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, 5 + each.value)
  tags              = { Name = "${var.name}-egress-${each.key}", Tier = "egress" }
}

resource "aws_subnet" "app" {
  for_each          = local.az_index
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, 10 + each.value)
  tags              = { Name = "${var.name}-app-${each.key}", Tier = "app" }
}

resource "aws_subnet" "data" {
  for_each          = local.az_index
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, 20 + each.value)
  tags              = { Name = "${var.name}-data-${each.key}", Tier = "data" }
}

resource "aws_subnet" "firewall" {
  for_each          = local.firewall
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 12, 480 + each.value)
  tags              = { Name = "${var.name}-firewall-${each.key}", Tier = "firewall" }
}

# ---------- NAT ----------

resource "aws_eip" "nat" {
  for_each = local.nat_azs
  domain   = "vpc"
  tags     = { Name = "${var.name}-nat-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = local.nat_azs
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.egress[each.key].id
  tags          = { Name = "${var.name}-${each.key}" }
  depends_on    = [aws_internet_gateway.this]
}

# ---------- route tables ----------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "egress" {
  for_each = local.az_index
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-egress-${each.key}" }
}

resource "aws_route" "egress_default" {
  for_each               = local.az_index
  route_table_id         = aws_route_table.egress[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# Return traffic from NAT back to the app subnet goes through the firewall too,
# so the firewall sees both directions (it is stateful).
resource "aws_route" "egress_to_app" {
  for_each               = local.firewall
  route_table_id         = aws_route_table.egress[each.key].id
  destination_cidr_block = aws_subnet.app[each.key].cidr_block
  vpc_endpoint_id        = local.firewall_endpoints[each.key]
}

resource "aws_route_table_association" "egress" {
  for_each       = aws_subnet.egress
  subnet_id      = each.value.id
  route_table_id = aws_route_table.egress[each.key].id
}

resource "aws_route_table" "firewall" {
  for_each = local.firewall
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-firewall-${each.key}" }
}

resource "aws_route" "firewall_default" {
  for_each               = local.firewall
  route_table_id         = aws_route_table.firewall[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.nat_for[each.key]].id
}

resource "aws_route_table_association" "firewall" {
  for_each       = aws_subnet.firewall
  subnet_id      = each.value.id
  route_table_id = aws_route_table.firewall[each.key].id
}

resource "aws_route_table" "app" {
  for_each = local.az_index
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-app-${each.key}" }
}

resource "aws_route" "app_default" {
  for_each               = local.az_index
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.enable_network_firewall ? local.firewall_endpoints[each.key] : null
  nat_gateway_id         = var.enable_network_firewall ? null : aws_nat_gateway.this[local.nat_for[each.key]].id
}

resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# Data subnets get only the local route and the S3 gateway endpoint.
resource "aws_route_table" "data" {
  for_each = local.az_index
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.name}-data-${each.key}" }
}

resource "aws_route_table_association" "data" {
  for_each       = aws_subnet.data
  subnet_id      = each.value.id
  route_table_id = aws_route_table.data[each.key].id
}

# ---------- flow logs ----------

resource "aws_cloudwatch_log_group" "flow" {
  name              = "/vpc/${var.name}/flow"
  retention_in_days = var.flow_log_retention_days
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_write" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role" "flow" {
  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json
}

resource "aws_iam_role_policy" "flow" {
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.flow_write.json
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow.arn
  iam_role_arn    = aws_iam_role.flow.arn
}
