# alb      443 from the internet (WAF in front)
# app      only from the ALB; HTTPS out
# pipeline no inbound at all; HTTPS out
# db       5432 from app and pipeline only

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public HTTPS"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Dagster and Metabase containers"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "pipeline" {
  name        = "${var.name}-pipeline"
  description = "dlt, Soda and dbt tasks: no inbound"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "https_out" {
  for_each          = { app = aws_security_group.app.id, pipeline = aws_security_group.pipeline.id }
  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_db" {
  for_each                     = { app = aws_security_group.app.id, pipeline = aws_security_group.pipeline.id }
  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres for Dagster and Metabase metadata"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from" {
  for_each                     = { app = aws_security_group.app.id, pipeline = aws_security_group.pipeline.id }
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
