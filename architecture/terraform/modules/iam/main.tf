# One role per job, so a bug in one cannot touch another's data:
#   ingest     (dlt)            write raw
#   transform  (Soda + dbt)     read raw, write staging and mart
#   dagster    (orchestrator)   read queues, start the two tasks above
#   metabase   (dashboards)     read mart only
# Table-level access is enforced again by Lake Formation (governance module).

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region  = data.aws_region.current.name
  account = data.aws_caller_identity.current.account_id
  glue    = "arn:aws:glue:${local.region}:${local.account}"
  db      = var.glue_database_names

  athena_actions = [
    "athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults",
    "athena:StopQueryExecution", "athena:GetWorkGroup", "athena:BatchGetQueryExecution",
  ]
  glue_read  = ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartition", "glue:GetPartitions"]
  glue_write = ["glue:CreateTable", "glue:UpdateTable", "glue:DeleteTable", "glue:BatchCreatePartition", "glue:BatchDeletePartition"]
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

# ---------- execution role (pull image, write logs, inject secrets) ----------

resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid     = "InjectSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    # rds!db-* is the password RDS creates and rotates itself; the rest are ours.
    resources = [
      "arn:aws:secretsmanager:${local.region}:${local.account}:secret:rds!db-*",
      "arn:aws:secretsmanager:${local.region}:${local.account}:secret:${var.name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "execution" {
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# ---------- ingest (dlt) ----------

data "aws_iam_policy_document" "ingest" {
  statement {
    sid       = "RawBucketReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.bucket_arns["raw"], "${var.bucket_arns["raw"]}/*"]
  }
  statement {
    sid       = "AthenaResults"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.bucket_arns["athena"], "${var.bucket_arns["athena"]}/*"]
  }
  statement {
    actions   = local.athena_actions
    resources = ["arn:aws:athena:${local.region}:${local.account}:workgroup/${var.athena_workgroup}"]
  }
  statement {
    actions   = concat(local.glue_read, local.glue_write)
    resources = ["${local.glue}:catalog", "${local.glue}:database/${local.db["raw"]}", "${local.glue}:table/${local.db["raw"]}/*"]
  }
  statement {
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arns["raw"], var.kms_key_arns["athena"]]
  }
  statement {
    sid       = "PublishRawLanded"
    actions   = ["events:PutEvents"]
    resources = [var.bus_arn]
  }
}

resource "aws_iam_role" "ingest" {
  name               = "${var.name}-ingest"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "ingest" {
  role   = aws_iam_role.ingest.id
  policy = data.aws_iam_policy_document.ingest.json
}

# ---------- transform (Soda + dbt) ----------

data "aws_iam_policy_document" "transform" {
  statement {
    sid       = "RawReadOnly"
    actions   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.bucket_arns["raw"], "${var.bucket_arns["raw"]}/*"]
  }
  statement {
    sid       = "LakeAndResultsReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.bucket_arns["lake"], "${var.bucket_arns["lake"]}/*", var.bucket_arns["athena"], "${var.bucket_arns["athena"]}/*"]
  }
  statement {
    actions   = local.athena_actions
    resources = ["arn:aws:athena:${local.region}:${local.account}:workgroup/${var.athena_workgroup}"]
  }
  statement {
    actions   = local.glue_read
    resources = ["${local.glue}:catalog", "${local.glue}:database/${local.db["raw"]}", "${local.glue}:table/${local.db["raw"]}/*"]
  }
  statement {
    actions = concat(local.glue_read, local.glue_write)
    resources = [
      "${local.glue}:catalog",
      "${local.glue}:database/${local.db["staging"]}", "${local.glue}:table/${local.db["staging"]}/*",
      "${local.glue}:database/${local.db["mart"]}", "${local.glue}:table/${local.db["mart"]}/*",
    ]
  }
  statement {
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arns["raw"], var.kms_key_arns["lake"], var.kms_key_arns["athena"]]
  }
  statement {
    sid       = "PublishQualityAndMartEvents"
    actions   = ["events:PutEvents"]
    resources = [var.bus_arn]
  }
}

resource "aws_iam_role" "transform" {
  name               = "${var.name}-transform"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "transform" {
  role   = aws_iam_role.transform.id
  policy = data.aws_iam_policy_document.transform.json
}

# ---------- dagster (webserver + daemon) ----------

data "aws_iam_policy_document" "dagster" {
  statement {
    sid       = "ConsumeQueues"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
    resources = values(var.queue_arns)
  }
  statement {
    sid     = "LaunchPipelineTasks"
    actions = ["ecs:RunTask"]
    resources = [
      "arn:aws:ecs:${local.region}:${local.account}:task-definition/${var.name}-ingest:*",
      "arn:aws:ecs:${local.region}:${local.account}:task-definition/${var.name}-transform:*",
    ]
  }
  statement {
    sid       = "WatchTasks"
    actions   = ["ecs:DescribeTasks", "ecs:StopTask", "ecs:ListTasks", "ecs:DescribeTaskDefinition", "ec2:DescribeNetworkInterfaces"]
    resources = ["*"]
  }
  statement {
    sid       = "PassOnlyPipelineRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ingest.arn, aws_iam_role.transform.arn, aws_iam_role.execution.arn]
  }
  statement {
    sid       = "ReadRunLogs"
    actions   = ["logs:GetLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:${local.region}:${local.account}:log-group:/ecs/${var.name}/*"]
  }
  statement {
    sid       = "PublishRunFailed"
    actions   = ["events:PutEvents"]
    resources = [var.bus_arn]
  }
}

resource "aws_iam_role" "dagster" {
  name               = "${var.name}-dagster"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "dagster" {
  role   = aws_iam_role.dagster.id
  policy = data.aws_iam_policy_document.dagster.json
}

# ---------- metabase (read marts through Athena) ----------

data "aws_iam_policy_document" "metabase" {
  statement {
    actions   = local.athena_actions
    resources = ["arn:aws:athena:${local.region}:${local.account}:workgroup/${var.athena_workgroup}"]
  }
  statement {
    actions   = local.glue_read
    resources = ["${local.glue}:catalog", "${local.glue}:database/${local.db["mart"]}", "${local.glue}:table/${local.db["mart"]}/*"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.bucket_arns["athena"], "${var.bucket_arns["athena"]}/*"]
  }
  statement {
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arns["lake"], var.kms_key_arns["athena"]]
  }
}

resource "aws_iam_role" "metabase" {
  name               = "${var.name}-metabase"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "metabase" {
  role   = aws_iam_role.metabase.id
  policy = data.aws_iam_policy_document.metabase.json
}

# ---------- CI deploys via GitHub OIDC (no stored AWS keys) ----------

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_github_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${local.account}:oidc-provider/token.actions.githubusercontent.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only the main branch and the protected "prod" environment may deploy.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main", "repo:${var.github_repo}:environment:prod"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each   = toset(var.deploy_policy_arns)
  role       = aws_iam_role.deploy.name
  policy_arn = each.value
}
