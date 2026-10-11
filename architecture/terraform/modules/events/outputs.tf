output "bus_name" {
  value = aws_cloudwatch_event_bus.this.name
}

output "bus_arn" {
  value = aws_cloudwatch_event_bus.this.arn
}

output "queue_urls" {
  value = { for k, q in aws_sqs_queue.this : k => q.url }
}

output "queue_arns" {
  value = { for k, q in aws_sqs_queue.this : k => q.arn }
}

output "alerts_topic_arn" {
  value = aws_sns_topic.this["alerts"].arn
}
