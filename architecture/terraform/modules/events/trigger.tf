# Nightly: EventBridge Scheduler -> Lambda -> reads the latest commit SHA of
# PokeAPI/api-data -> publishes ingest.requested with that SHA. The Dagster
# sensor uses the SHA as its run key, so an unchanged commit never runs twice.

data "archive_file" "check_commit" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.root}/.build/check_commit.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "check_commit" {
  name               = "${var.name}-check-commit"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "check_commit_vpc" {
  role       = aws_iam_role.check_commit.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "check_commit" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.this.arn]
  }
}

resource "aws_iam_role_policy" "check_commit" {
  role   = aws_iam_role.check_commit.id
  policy = data.aws_iam_policy_document.check_commit.json
}

resource "aws_security_group" "check_commit" {
  name        = "${var.name}-check-commit"
  description = "Commit checker Lambda: HTTPS out only"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to api.github.com (via the allowlist) and AWS endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "check_commit" {
  name              = "/aws/lambda/${var.name}-check-commit"
  retention_in_days = 90
}

resource "aws_lambda_function" "check_commit" {
  function_name    = "${var.name}-check-commit"
  role             = aws_iam_role.check_commit.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.check_commit.output_path
  source_code_hash = data.archive_file.check_commit.output_base64sha256
  timeout          = 30
  architectures    = ["arm64"]

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.this.name
      REPO           = "PokeAPI/api-data"
    }
  }

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [aws_security_group.check_commit.id]
  }

  depends_on = [aws_cloudwatch_log_group.check_commit]
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler" {
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.check_commit.arn
    }]
  })
}

resource "aws_scheduler_schedule" "nightly" {
  name                         = "${var.name}-nightly"
  schedule_expression          = var.schedule
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.check_commit.arn
    role_arn = aws_iam_role.scheduler.arn
    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}
