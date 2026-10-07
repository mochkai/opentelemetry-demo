# Customer-owned archive storage for Coralogix (AWS side only). The buckets are
# connected to the Coralogix team in the UI: Data Flow -> Setup Archive.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Owner     = var.owner
    }
  }
}

variable "project" {
  description = "Name prefix for all resources."
  type        = string
  default     = "cx-otel-lab"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "thiago"
}

# Coralogix EU2 runs in eu-north-1 (Stockholm); archive buckets must be in the team's region.
variable "region" {
  description = "AWS region. Must match the Coralogix team's region."
  type        = string
  default     = "eu-north-1"
}

output "region" {
  value = var.region
}
