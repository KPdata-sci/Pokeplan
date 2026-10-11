terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }

  # State lives in the shared-services account; one key per environment.
  # terraform init -backend-config=backend-prod.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "pokeplan"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
