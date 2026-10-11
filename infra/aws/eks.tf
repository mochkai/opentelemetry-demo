data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  cluster_name = "${var.project}-eks"
  azs          = slice(data.aws_availability_zones.available.names, 0, 3)

  # IAM principals that get read-only access to every cluster resource. IAM alone
  # isn't enough to see nodes/pods in the EKS console: the principal also needs a
  # Kubernetes identity, granted here via EKS access entries.
  console_viewers = merge(
    var.grant_root_console_view ? { account-root = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" } : {},
    var.console_viewers,
  )
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project}-vpc"
  cidr = "10.42.0.0/16"
  azs  = local.azs

  private_subnets = ["10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"]
  public_subnets  = ["10.42.48.0/24", "10.42.49.0/24", "10.42.50.0/24"]

  # Lab trade-off: one NAT gateway instead of one per AZ (cheaper, not HA).
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  # Public API endpoint so kubectl works from a laptop. Restrict CIDRs in real use.
  endpoint_public_access = true

  # Grants the identity running terraform cluster-admin via EKS access entries.
  enable_cluster_creator_admin_permissions = true

  # AmazonEKSAdminViewPolicy, not AmazonEKSViewPolicy: the latter maps to the
  # Kubernetes "view" role, which excludes cluster-scoped objects like nodes, so the
  # console shows pods but no nodes. AdminView is read-only but can read Secrets.
  access_entries = {
    for name, arn in local.console_viewers : "console-${name}" => {
      principal_arn = arn
      policy_associations = {
        admin-view = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 2
      max_size       = 4
      desired_size   = var.node_desired_size

      # Default would be "default-eks-node-group-*"; keep every IAM name under the
      # project prefix so the deployer's IAM permissions can be scoped to it.
      iam_role_name = "${local.cluster_name}-node"
    }
  }
}
