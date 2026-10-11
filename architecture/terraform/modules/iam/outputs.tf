output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arns" {
  value = {
    ingest    = aws_iam_role.ingest.arn
    transform = aws_iam_role.transform.arn
    dagster   = aws_iam_role.dagster.arn
    metabase  = aws_iam_role.metabase.arn
  }
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}
