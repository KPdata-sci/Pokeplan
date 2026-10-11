variable "admin_arns" {
  description = "IAM principals that administer Lake Formation (e.g. the Identity Center data-platform-admin role)."
  type        = list(string)
}

variable "bucket_arns" {
  type = map(string)
}

variable "glue_database_names" {
  type = map(string)
}

variable "task_role_arns" {
  description = "From the iam module: ingest, transform, metabase."
  type        = map(string)
}

variable "analyst_role_arns" {
  description = "People who may query the marts directly in Athena, besides Metabase."
  type        = list(string)
  default     = []
}
