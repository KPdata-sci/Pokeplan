output "bucket_names" {
  value = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "bucket_arns" {
  value = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "kms_key_arns" {
  value = { for k, key in aws_kms_key.this : k => key.arn }
}

output "glue_database_names" {
  value = { for k, db in aws_glue_catalog_database.this : k => db.name }
}

output "athena_workgroup" {
  value = aws_athena_workgroup.pipeline.name
}
