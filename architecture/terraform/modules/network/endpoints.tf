# S3 is a free gateway endpoint on the app and data route tables. Everything else
# is an interface endpoint (about $7.30 per service per AZ per month).

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([for rt in aws_route_table.app : rt.id], [for rt in aws_route_table.data : rt.id])
  tags              = { Name = "${var.name}-s3" }
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-endpoints"
  description = "HTTPS from inside the VPC to AWS interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.interface_endpoints)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.app : s.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  tags                = { Name = "${var.name}-${each.key}" }
}
