# Learning layout: about $70 a month. Same modules, cheaper switches.
# Network Firewall off -> DNS Firewall allowlist on; one NAT; AWS APIs through NAT.
# Note: subnets still span 2 AZs because the ALB and RDS subnet group require it;
# only the NAT and the database stay in one.
environment             = "learning"
az_count                = 2
single_nat_gateway      = true
enable_network_firewall = false
interface_endpoints     = []
db_multi_az             = false
deletion_protection     = false

domain                   = "learn.pokeplan.example.com"
certificate_arn          = "arn:aws:acm:eu-west-2:222222222222:certificate/REPLACE-ME"
lakeformation_admin_arns = ["arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_REPLACE"]
github_repo              = "KPdata-sci/pokeplan"
