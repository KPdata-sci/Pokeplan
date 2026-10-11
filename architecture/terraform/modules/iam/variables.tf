variable "name" {
  type = string
}

variable "bucket_arns" {
  description = "From the storage module: raw, lake, athena."
  type        = map(string)
}

variable "kms_key_arns" {
  type = map(string)
}

variable "glue_database_names" {
  description = "From the storage module: raw, staging, mart."
  type        = map(string)
}

variable "athena_workgroup" {
  type = string
}

variable "bus_arn" {
  type = string
}

variable "queue_arns" {
  type = map(string)
}

variable "github_repo" {
  description = "owner/repo allowed to deploy through GitHub Actions OIDC."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Only one GitHub OIDC provider can exist per account; set false if another stack made it."
  type        = bool
  default     = true
}

variable "deploy_policy_arns" {
  description = "Policies for the CI deploy role. Scope these down in a real org (permissions boundary)."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
}
