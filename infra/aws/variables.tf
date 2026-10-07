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
  # Must be explicit: with null the node group derives its version from the cluster,
  # which is unknown until apply and breaks planning (module count dependency).
  # 1.36 = EKS default in eu-north-1, standard support until 2027-08 (check with
  # `aws eks describe-cluster-versions` to avoid paid extended support).
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "Worker node instance type. The OTel Demo needs ~6-8 GiB across the cluster."
  type        = string
  # m7i-flex.large (2 vCPU / 8 GiB) is the largest type allowed on an AWS Free plan
  # account; t3.large fails with "not eligible for Free Tier".
  default = "m7i-flex.large"
}

variable "node_desired_size" {
  type    = number
  default = 3
}
