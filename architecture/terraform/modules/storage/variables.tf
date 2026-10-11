variable "name" {
  type = string
}

variable "s3_endpoint_id" {
  description = "Writes to the data buckets must arrive through this VPC endpoint (or via Athena)."
  type        = string
}

variable "athena_bytes_scanned_cutoff" {
  description = "Per-query scan limit for the pipeline workgroup, as a cost guard."
  type        = number
  default     = 10737418240 # 10 GiB
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete non-empty buckets. Keep false in prod."
  type        = bool
  default     = false
}
