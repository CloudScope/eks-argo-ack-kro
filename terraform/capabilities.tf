# ACK Capability IAM Role
resource "aws_iam_role" "ack_capability" {
  count = var.enable_ack_capability ? 1 : 0
  name  = "${var.cluster_name}-ack-capability-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "capabilities.eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-ack-capability-role"
    }
  )
}

# KRO Capability IAM Role
resource "aws_iam_role" "kro_capability" {
  count = var.enable_kro_capability ? 1 : 0
  name  = "${var.cluster_name}-kro-capability-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "capabilities.eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-kro-capability-role"
    }
  )
}

# ArgoCD Capability IAM Role
resource "aws_iam_role" "argocd_capability" {
  count = var.enable_argocd_capability ? 1 : 0
  name  = "${var.cluster_name}-argocd-capability-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "capabilities.eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-argocd-capability-role"
    }
  )
}

# Enable ACK Capability
resource "aws_eks_capability" "ack" {
  count                     = var.enable_ack_capability ? 1 : 0
  cluster_name              = aws_eks_cluster.main.name
  capability_name           = "ack"
  type                      = "ACK"
  role_arn                  = aws_iam_role.ack_capability[0].arn
  delete_propagation_policy = "RETAIN"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-ack-capability"
    }
  )

  depends_on = [aws_eks_cluster.main]
}

# Enable KRO Capability
resource "aws_eks_capability" "kro" {
  count                     = var.enable_kro_capability ? 1 : 0
  cluster_name              = aws_eks_cluster.main.name
  capability_name           = "kro"
  type                      = "KRO"
  role_arn                  = aws_iam_role.kro_capability[0].arn
  delete_propagation_policy = "RETAIN"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-kro-capability"
    }
  )

  depends_on = [aws_eks_cluster.main]
}

# AWS supports exactly one IAM Identity Center instance per organization/account, so
# it can be resolved automatically rather than asking for the ARN to be pasted in.
data "aws_ssoadmin_instances" "this" {
  count = var.enable_argocd_capability ? 1 : 0
}

# AWS best practice: map a group (not individual users) to the ArgoCD ADMIN role
resource "aws_identitystore_group" "argocd_admin" {
  count             = var.enable_argocd_capability ? 1 : 0
  identity_store_id = tolist(data.aws_ssoadmin_instances.this[0].identity_store_ids)[0]
  display_name      = var.argocd_admin_group_name
  description       = "Full (ADMIN) access to the ${var.cluster_name} ArgoCD capability"
}

# Enable ArgoCD Capability
resource "aws_eks_capability" "argocd" {
  count                     = var.enable_argocd_capability ? 1 : 0
  cluster_name              = aws_eks_cluster.main.name
  capability_name           = "argocd"
  type                      = "ARGOCD"
  role_arn                  = aws_iam_role.argocd_capability[0].arn
  delete_propagation_policy = "RETAIN"

  configuration {
    argo_cd {
      namespace = "argocd"

      # No network_access.vpce_ids block - that's what restricts the Argo CD endpoint
      # to private VPC-only access via PrivateLink. Leaving it unset is deliberate:
      # the server stays reachable over the public internet, gated by the aws_idc/
      # rbac_role_mapping SSO login below.

      aws_idc {
        idc_instance_arn = tolist(data.aws_ssoadmin_instances.this[0].arns)[0]
      }

      rbac_role_mapping {
        role = "ADMIN"

        identity {
          id   = aws_identitystore_group.argocd_admin[0].group_id
          type = "SSO_GROUP"
        }
      }
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-argocd-capability"
    }
  )

  depends_on = [aws_eks_cluster.main]
}

# ACK capability needs to read Kubernetes secrets it doesn't own (e.g. DB passwords) -
# grant it via an EKS access entry, per AWS guidance for the ACK capability
resource "aws_eks_access_entry" "ack_capability" {
  count         = var.enable_ack_capability ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.ack_capability[0].arn

  depends_on = [aws_eks_capability.ack]
}

resource "aws_eks_access_policy_association" "ack_secret_reader" {
  count         = var.enable_ack_capability ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSSecretReaderPolicy"
  principal_arn = aws_iam_role.ack_capability[0].arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.ack_capability]
}
