# Lake Formation is the second lock on the data. IAM says a role may call Glue
# and Athena; these grants say which databases and tables it may see.
#
#   ingest     raw: create and write tables
#   transform  raw: read; staging and mart: create and write
#   metabase   mart: read
#   analysts   mart: read

resource "aws_lakeformation_data_lake_settings" "this" {
  admins = var.admin_arns

  # Turn off the legacy "IAM only" default so new tables are governed by grants.
  create_database_default_permissions {}
  create_table_default_permissions {}
}

resource "aws_lakeformation_resource" "this" {
  for_each                = { raw = var.bucket_arns["raw"], lake = var.bucket_arns["lake"] }
  arn                     = each.value
  use_service_linked_role = true
  hybrid_access_enabled   = false
  depends_on              = [aws_lakeformation_data_lake_settings.this]
}

locals {
  db = var.glue_database_names

  # who -> database -> permissions on the database, and on every table in it
  writers = {
    ingest_raw        = { role = var.task_role_arns["ingest"], db = local.db["raw"], location = "raw" }
    transform_staging = { role = var.task_role_arns["transform"], db = local.db["staging"], location = "lake" }
    transform_mart    = { role = var.task_role_arns["transform"], db = local.db["mart"], location = "lake" }
  }
  readers = merge(
    {
      transform_raw = { role = var.task_role_arns["transform"], db = local.db["raw"] }
      metabase_mart = { role = var.task_role_arns["metabase"], db = local.db["mart"] }
    },
    { for i, arn in var.analyst_role_arns : "analyst_${i}_mart" => { role = arn, db = local.db["mart"] } },
  )
}

resource "aws_lakeformation_permissions" "writer_location" {
  for_each    = local.writers
  principal   = each.value.role
  permissions = ["DATA_LOCATION_ACCESS"]
  data_location {
    arn = aws_lakeformation_resource.this[each.value.location].arn
  }
}

resource "aws_lakeformation_permissions" "writer_db" {
  for_each    = local.writers
  principal   = each.value.role
  permissions = ["CREATE_TABLE", "ALTER", "DESCRIBE"]
  database {
    name = each.value.db
  }
}

resource "aws_lakeformation_permissions" "writer_tables" {
  for_each    = local.writers
  principal   = each.value.role
  permissions = ["SELECT", "INSERT", "DELETE", "ALTER", "DROP", "DESCRIBE"]
  table {
    database_name = each.value.db
    wildcard      = true
  }
}

resource "aws_lakeformation_permissions" "reader_db" {
  for_each    = local.readers
  principal   = each.value.role
  permissions = ["DESCRIBE"]
  database {
    name = each.value.db
  }
}

resource "aws_lakeformation_permissions" "reader_tables" {
  for_each    = local.readers
  principal   = each.value.role
  permissions = ["SELECT", "DESCRIBE"]
  table {
    database_name = each.value.db
    wildcard      = true
  }
}
