# Plans both layouts against a mocked AWS provider: no credentials, nothing created.
# Run: terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-2a", "eu-west-2b", "eu-west-2c"] }
  }
  mock_data "aws_region" {
    defaults = { name = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_networkfirewall_firewall" {
    defaults = {
      firewall_status = [{
        sync_states = [
          { availability_zone = "eu-west-2a", attachment = [{ endpoint_id = "vpce-fw-a", subnet_id = "subnet-a", status = "READY" }] },
          { availability_zone = "eu-west-2b", attachment = [{ endpoint_id = "vpce-fw-b", subnet_id = "subnet-b", status = "READY" }] },
        ]
      }]
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address            = "pokeplan.abc.eu-west-2.rds.amazonaws.com"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:eu-west-2:111111111111:secret:rds!db-123", kms_key_id = "k", secret_status = "active" }]
    }
  }
}

variables {
  oidc = {
    issuer                 = "https://idp.example.com"
    authorization_endpoint = "https://idp.example.com/authorize"
    token_endpoint         = "https://idp.example.com/token"
    user_info_endpoint     = "https://idp.example.com/userinfo"
    client_id              = "pokeplan"
    client_secret          = "test-only"
  }
  domain                   = "pokeplan.example.com"
  certificate_arn          = "arn:aws:acm:eu-west-2:111111111111:certificate/test"
  lakeformation_admin_arns = ["arn:aws:iam::111111111111:role/admin"]
  github_repo              = "KPdata-sci/pokeplan"
  vpc_cidr                 = "10.40.0.0/16"
}

run "prod_layout" {
  command = plan
  variables {
    environment             = "prod"
    az_count                = 2
    single_nat_gateway      = false
    enable_network_firewall = true
    interface_endpoints     = ["ecr.api", "ecr.dkr", "ecs", "logs", "sts", "secretsmanager", "kms", "sqs", "events", "sns", "athena", "glue"]
    db_multi_az             = true
    deletion_protection     = true
  }

  assert {
    condition     = length(module.network.app_subnet_ids) == 2
    error_message = "expected app subnets in 2 AZs"
  }
}

run "learning_layout" {
  command = plan
  variables {
    environment             = "learning"
    az_count                = 2
    single_nat_gateway      = true
    enable_network_firewall = false
    interface_endpoints     = []
    db_multi_az             = false
    deletion_protection     = false
  }

  assert {
    condition     = length(module.network.data_subnet_ids) == 2
    error_message = "expected data subnets in 2 AZs"
  }
}
