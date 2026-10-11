variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arns" {
  description = "From the iam module: ingest, transform, dagster, metabase."
  type        = map(string)
}

variable "image_tag" {
  description = "Tag of the dagster and pipeline images in ECR (CI pushes them)."
  type        = string
  default     = "latest"
}

variable "metabase_version" {
  description = "Tag of the Metabase image mirrored into ECR."
  type        = string
  default     = "v0.50.30"
}

variable "domain" {
  description = "Parent domain; the ALB serves metabase.<domain> and dagster.<domain>."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate covering both hostnames."
  type        = string
}

variable "oidc" {
  description = "Your identity provider (IAM Identity Center via an OIDC app, Okta, Entra ID...). The ALB signs people in before any request reaches a container."
  type = object({
    issuer                 = string
    authorization_endpoint = string
    token_endpoint         = string
    user_info_endpoint     = string
    client_id              = string
    client_secret          = string
  })
  sensitive = true
}

variable "pipeline_env" {
  description = "Environment passed to Dagster and pipeline tasks: bus, queues, buckets, workgroup, Glue databases."
  type        = map(string)
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "dagster_desired_count" {
  description = "Set to 0 to stop Dagster between learning sessions."
  type        = number
  default     = 1
}

variable "metabase_desired_count" {
  type    = number
  default = 1
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "log_retention_days" {
  type    = number
  default = 90
}
