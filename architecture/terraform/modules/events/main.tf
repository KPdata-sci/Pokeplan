# The pokeplan event bus. Producers publish; rules route each detail-type to a
# queue (for Dagster sensors) or a topic (for people).
#
#   ingest.requested -> SQS ingest     -> Dagster ingest job
#   raw.landed       -> SQS transform  -> Dagster transform job
#   quality.failed   -> SNS alerts
#   run.failed       -> SNS alerts
#   mart.refreshed   -> SNS digest

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  source = "pokeplan"
  queues = {
    ingest    = "ingest.requested"
    transform = "raw.landed"
  }
  topics = {
    alerts = ["quality.failed", "run.failed"]
    digest = ["mart.refreshed"]
  }
}

resource "aws_cloudwatch_event_bus" "this" {
  name = var.name
}

resource "aws_cloudwatch_event_archive" "all" {
  name             = var.name
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  retention_days   = var.archive_retention_days
}

# ---------- queues for Dagster sensors ----------

resource "aws_sqs_queue" "dlq" {
  for_each                  = local.queues
  name                      = "${var.name}-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "this" {
  for_each                   = local.queues
  name                       = "${var.name}-${each.key}"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600 # 4 days
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = 3
  })
}

resource "aws_cloudwatch_event_rule" "queue" {
  for_each       = local.queues
  name           = "${var.name}-${each.key}"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  event_pattern = jsonencode({
    source        = [local.source]
    "detail-type" = [each.value]
  })
}

resource "aws_cloudwatch_event_target" "queue" {
  for_each       = local.queues
  rule           = aws_cloudwatch_event_rule.queue[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  arn            = aws_sqs_queue.this[each.key].arn
}

data "aws_iam_policy_document" "queue" {
  for_each = local.queues
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.this[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.queue[each.key].arn]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  for_each  = local.queues
  queue_url = aws_sqs_queue.this[each.key].id
  policy    = data.aws_iam_policy_document.queue[each.key].json
}

# Alarm when anything lands in a dead-letter queue.
resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each            = local.queues
  alarm_name          = "${var.name}-${each.key}-dlq-not-empty"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq[each.key].name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.this["alerts"].arn]
}

# ---------- topics for people ----------

resource "aws_sns_topic" "this" {
  for_each          = local.topics
  name              = "${var.name}-${each.key}"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_cloudwatch_event_rule" "topic" {
  for_each       = local.topics
  name           = "${var.name}-${each.key}"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  event_pattern = jsonencode({
    source        = [local.source]
    "detail-type" = each.value
  })
}

resource "aws_cloudwatch_event_target" "topic" {
  for_each       = local.topics
  rule           = aws_cloudwatch_event_rule.topic[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  arn            = aws_sns_topic.this[each.key].arn
}

data "aws_iam_policy_document" "topic" {
  for_each = local.topics
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  for_each = local.topics
  arn      = aws_sns_topic.this[each.key].arn
  policy   = data.aws_iam_policy_document.topic[each.key].json
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = var.alert_email == "" ? toset([]) : toset(["alerts", "digest"])
  topic_arn = aws_sns_topic.this[each.key].arn
  protocol  = "email"
  endpoint  = var.alert_email
}
