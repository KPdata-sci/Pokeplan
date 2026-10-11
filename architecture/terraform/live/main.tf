locals {
  name = "pokeplan-${var.environment}"
}

module "network" {
  source = "../modules/network"

  name                    = local.name
  cidr                    = var.vpc_cidr
  az_count                = var.az_count
  single_nat_gateway      = var.single_nat_gateway
  enable_network_firewall = var.enable_network_firewall
  interface_endpoints     = var.interface_endpoints
}

module "storage" {
  source = "../modules/storage"

  name           = local.name
  s3_endpoint_id = module.network.s3_endpoint_id
  force_destroy  = !var.deletion_protection
}

module "events" {
  source = "../modules/events"

  name              = local.name
  vpc_id            = module.network.vpc_id
  lambda_subnet_ids = module.network.app_subnet_ids
  lambda_source_dir = "${path.root}/../lambdas/check_commit"
  alert_email       = var.alert_email
}

module "iam" {
  source = "../modules/iam"

  name                = local.name
  bucket_arns         = module.storage.bucket_arns
  kms_key_arns        = module.storage.kms_key_arns
  glue_database_names = module.storage.glue_database_names
  athena_workgroup    = module.storage.athena_workgroup
  bus_arn             = module.events.bus_arn
  queue_arns          = module.events.queue_arns
  github_repo         = var.github_repo
}

module "governance" {
  source = "../modules/governance"

  admin_arns          = var.lakeformation_admin_arns
  bucket_arns         = module.storage.bucket_arns
  glue_database_names = module.storage.glue_database_names
  task_role_arns      = module.iam.task_role_arns
  analyst_role_arns   = var.analyst_role_arns
}

module "compute" {
  source = "../modules/compute"

  name                = local.name
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  app_subnet_ids      = module.network.app_subnet_ids
  data_subnet_ids     = module.network.data_subnet_ids
  execution_role_arn  = module.iam.execution_role_arn
  task_role_arns      = module.iam.task_role_arns
  image_tag           = var.image_tag
  domain              = var.domain
  certificate_arn     = var.certificate_arn
  oidc                = var.oidc
  db_multi_az         = var.db_multi_az
  deletion_protection = var.deletion_protection

  dagster_desired_count = var.environment == "prod" ? 1 : 0

  # What the Dagster code and the dlt/dbt tasks read at runtime.
  pipeline_env = {
    AWS_REGION          = var.region
    EVENT_BUS_NAME      = module.events.bus_name
    INGEST_QUEUE_URL    = module.events.queue_urls["ingest"]
    TRANSFORM_QUEUE_URL = module.events.queue_urls["transform"]
    RAW_BUCKET          = module.storage.bucket_names["raw"]
    LAKE_BUCKET         = module.storage.bucket_names["lake"]
    ATHENA_WORKGROUP    = module.storage.athena_workgroup
    GLUE_DB_RAW         = module.storage.glue_database_names["raw"]
    GLUE_DB_STAGING     = module.storage.glue_database_names["staging"]
    GLUE_DB_MART        = module.storage.glue_database_names["mart"]
  }
}
