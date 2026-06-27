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

# EKS validates the capability role's trust policy against IAM at creation time, and
# IAM trust policy changes take a few seconds to propagate. Without a wait, CreateCapability
# can fail with "trust policy is invalid" even though the policy content is correct -
# it's racing IAM's own eventual consistency, not a config error. The trigger keys off
# the policy content so any future trust policy change re-waits too, not just first create.
resource "time_sleep" "ack_capability_role" {
  count           = var.enable_ack_capability ? 1 : 0
  create_duration = "20s"

  triggers = {
    assume_role_policy = aws_iam_role.ack_capability[0].assume_role_policy
  }

  depends_on = [aws_iam_role.ack_capability]
}

resource "time_sleep" "kro_capability_role" {
  count           = var.enable_kro_capability ? 1 : 0
  create_duration = "20s"

  triggers = {
    assume_role_policy = aws_iam_role.kro_capability[0].assume_role_policy
  }

  depends_on = [aws_iam_role.kro_capability]
}

resource "time_sleep" "argocd_capability_role" {
  count           = var.enable_argocd_capability ? 1 : 0
  create_duration = "20s"

  triggers = {
    assume_role_policy = aws_iam_role.argocd_capability[0].assume_role_policy
  }

  depends_on = [aws_iam_role.argocd_capability]
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

  depends_on = [aws_eks_cluster.main, time_sleep.ack_capability_role]
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

  depends_on = [aws_eks_cluster.main, time_sleep.kro_capability_role]
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

  depends_on = [aws_eks_cluster.main, time_sleep.argocd_capability_role]
}

# ACK capability needs to read Kubernetes secrets it doesn't own (e.g. DB passwords).
# EKS automatically creates an access entry for the capability role when the capability
# itself is created - creating our own aws_eks_access_entry here would conflict with
# that auto-created one (ResourceInUseException). We only need to associate the extra
# secret-reader policy onto the entry EKS already made.
resource "aws_eks_access_policy_association" "ack_secret_reader" {
  count         = var.enable_ack_capability ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSSecretReaderPolicy"
  principal_arn = aws_iam_role.ack_capability[0].arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_capability.ack]
}
