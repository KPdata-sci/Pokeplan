# Production layout: about $800 a month, mostly Network Firewall and endpoints.
environment             = "prod"
az_count                = 2
single_nat_gateway      = false
enable_network_firewall = true
interface_endpoints     = ["ecr.api", "ecr.dkr", "ecs", "logs", "sts", "secretsmanager", "kms", "sqs", "events", "sns", "athena", "glue"]
db_multi_az             = true
deletion_protection     = true

domain                   = "pokeplan.example.com"
certificate_arn          = "arn:aws:acm:eu-west-2:111111111111:certificate/REPLACE-ME"
lakeformation_admin_arns = ["arn:aws:iam::111111111111:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_DataPlatformAdmin_REPLACE"]
github_repo              = "KPdata-sci/pokeplan"
# oidc = { ... }  pass via TF_VAR_oidc from CI secrets, never commit the client secret
