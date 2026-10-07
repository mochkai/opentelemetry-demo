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

# Coralogix EU2 runs in eu-north-1 (Stockholm). Archive buckets MUST be in the
# same region as the Coralogix team, so keep everything here.
variable "region" {
  description = "AWS region. Must match the Coralogix team's region for the archive."
  type        = string
  default     = "eu-north-1"
}

variable "kubernetes_version" {
  description = "EKS version. null = EKS default (avoids accidentally landing on a version in paid extended support)."
  type        = string
  default     = null
}

variable "node_instance_type" {
  description = "Worker node instance type. The OTel Demo needs ~6-8 GiB across the cluster."
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  type    = number
  default = 3
}
