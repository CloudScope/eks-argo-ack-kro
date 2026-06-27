# All cluster subnets (public + private) span both AZ groups created in main.tf
locals {
  all_subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  # API_AND_CONFIG_MAP is required for EKS access entries, which the ACK capability needs
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  vpc_config {
    subnet_ids              = local.all_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.cluster.id]
  }

  # Enable control plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(
    var.common_tags,
    {
      Name = var.cluster_name
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller
  ]
}

# EKS Pod Identity Agent addon (required for any Pod Identity association to work)
resource "aws_eks_addon" "pod_identity_agent" {
  count         = var.enable_pod_identity ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = data.aws_eks_addon_version.pod_identity_agent[0].version
  preserve      = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-pod-identity-agent"
    }
  )
}

data "aws_eks_addon_version" "pod_identity_agent" {
  count              = var.enable_pod_identity ? 1 : 0
  addon_name         = "eks-pod-identity-agent"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

# VPC CNI IAM Role - granted to the aws-node service account via Pod Identity
resource "aws_iam_role" "vpc_cni" {
  count = var.enable_vpc_cni ? 1 : 0
  name  = "${var.cluster_name}-vpc-cni-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-vpc-cni-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count      = var.enable_vpc_cni ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni[0].name
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  count           = var.enable_vpc_cni && var.enable_pod_identity ? 1 : 0
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni[0].arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

# EKS Addons
resource "aws_eks_addon" "vpc_cni" {
  count                       = var.enable_vpc_cni ? 1 : 0
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni[0].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  preserve                    = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-vpc-cni"
    }
  )

  depends_on = [aws_eks_pod_identity_association.vpc_cni]
}

# Get VPC CNI addon version
data "aws_eks_addon_version" "vpc_cni" {
  count              = var.enable_vpc_cni ? 1 : 0
  addon_name         = "vpc-cni"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

# CoreDNS Addon
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  preserve                    = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-coredns"
    }
  )

  depends_on = [aws_eks_node_group.on_demand, aws_eks_node_group.spot]
}

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

# kube-proxy Addon
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  preserve                    = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-kube-proxy"
    }
  )

  depends_on = [aws_eks_node_group.on_demand, aws_eks_node_group.spot]
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = var.cluster_version
  most_recent        = true
}
