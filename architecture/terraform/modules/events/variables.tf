variable "name" {
  type = string
}

variable "lambda_subnet_ids" {
  description = "App subnets; the commit checker reaches api.github.com through the egress allowlist."
  type        = list(string)
}

variable "vpc_id" {
  type = string
}

variable "lambda_source_dir" {
  description = "Folder holding handler.py for the commit checker."
  type        = string
}

variable "schedule" {
  description = "When to check PokeAPI/api-data for a new commit (EventBridge Scheduler syntax)."
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "schedule_timezone" {
  type    = string
  default = "Europe/London"
}

variable "alert_email" {
  description = "Optional address subscribed to alerts. Leave empty to subscribe Slack or PagerDuty some other way."
  type        = string
  default     = ""
}

variable "archive_retention_days" {
  description = "How long every event is kept for replay."
  type        = number
  default     = 30
}
