variable "environment" {
  description = "prod or learning."
  type        = string
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

# --- the switches that separate the production layout from the cheap one ---

variable "az_count" {
  type = number
}

variable "single_nat_gateway" {
  type = bool
}

variable "enable_network_firewall" {
  type = bool
}

variable "interface_endpoints" {
  type = list(string)
}

variable "db_multi_az" {
  type = bool
}

variable "deletion_protection" {
  type = bool
}

# --- things only you know ---

variable "domain" {
  description = "e.g. pokeplan.example.com; serves metabase.<domain> and dagster.<domain>."
  type        = string
}

variable "certificate_arn" {
  type = string
}

variable "oidc" {
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

variable "lakeformation_admin_arns" {
  type = list(string)
}

variable "analyst_role_arns" {
  type    = list(string)
  default = []
}

variable "github_repo" {
  description = "owner/repo whose main branch may deploy."
  type        = string
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "image_tag" {
  type    = string
  default = "latest"
}
