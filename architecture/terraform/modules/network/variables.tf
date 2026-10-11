variable "name" {
  description = "Prefix for every resource name, e.g. pokeplan-prod."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR. Subnets are carved from it as /24s (and /28s for the firewall)."
  type        = string
  default     = "10.40.0.0/16"
}

variable "az_count" {
  description = "How many availability zones to spread over."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "One NAT gateway for the whole VPC instead of one per AZ (cheaper, not zone-resilient)."
  type        = bool
  default     = false
}

variable "enable_network_firewall" {
  description = "Route all outbound traffic through AWS Network Firewall with a domain allowlist."
  type        = bool
  default     = true
}

variable "egress_domains" {
  description = "Domains Network Firewall lets out (TLS SNI / HTTP Host). A leading dot also matches subdomains."
  type        = list(string)
  default     = ["pokeapi.co", ".pokeapi.co", "github.com", ".github.com", ".githubusercontent.com"]
}

variable "enable_dns_firewall" {
  description = "When Network Firewall is off, use Route 53 Resolver DNS Firewall as a cheaper allowlist."
  type        = bool
  default     = true
}

variable "dns_allowed_domains" {
  description = "Names the VPC resolver will answer when DNS Firewall is on. Everything else gets NXDOMAIN."
  type        = list(string)
  default = [
    "pokeapi.co.", "*.pokeapi.co.",
    "github.com.", "*.github.com.", "*.githubusercontent.com.",
    "*.amazonaws.com.", "*.aws.", "*.internal.",
  ]
}

variable "interface_endpoints" {
  description = "AWS services reached through PrivateLink instead of the internet. Empty list = go through NAT."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "ecs", "logs", "sts", "secretsmanager", "kms", "sqs", "events", "sns", "athena", "glue"]
}

variable "flow_log_retention_days" {
  type    = number
  default = 90
}
