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

# AWS resources ACK is allowed to manage from Kubernetes CRs, scoped per service.
# IAMFullAccess and ec2:* (which covers VPC) are genuinely high blast-radius grants -
# anyone with merge access to the GitOps repos can effectively create/escalate IAM
# roles or modify VPC networking through an ACK custom resource. Requested explicitly;
# narrow these to scoped custom policies later if that risk needs reducing.
locals {
  ack_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess", # also covers VPC - same API namespace
    "arn:aws:iam::aws:policy/CloudWatchFullAccessV2", # CloudWatchFullAccess is deprecated
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
    "arn:aws:iam::aws:policy/IAMFullAccess",
  ]
}

resource "aws_iam_role_policy_attachment" "ack_managed" {
  for_each   = var.enable_ack_capability ? toset(local.ack_managed_policy_arns) : []
  role       = aws_iam_role.ack_capability[0].name
  policy_arn = each.value
}

# No AWS managed policy fits the EKS controller - this is ACK's own recommended inline
# policy for the eks.services.k8s.aws controller (config/iam/recommended-inline-policy
# in aws-controllers-k8s/eks-controller), not a guess.
resource "aws_iam_policy" "ack_eks" {
  count       = var.enable_ack_capability ? 1 : 0
  name        = "${var.cluster_name}-ack-eks-controller"
  description = "ACK eks.services.k8s.aws controller's recommended inline policy - no AWS managed policy covers this"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:*",
          "iam:GetRole",
          "iam:PassRole",
          "iam:ListAttachedRolePolicies",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ack_eks" {
  count      = var.enable_ack_capability ? 1 : 0
  policy_arn = aws_iam_policy.ack_eks[0].arn
  role       = aws_iam_role.ack_capability[0].name
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

# The auto-granted AmazonEKSKROPolicy only covers kro's own CRDs/ResourceGraphDefinitions -
# it can read an RGD but not act on what it composes (e.g. create the ACK resources or
# Deployments an RGD instantiates). This is what actually lets kro create things, cluster-wide.
resource "aws_eks_access_policy_association" "kro_edit" {
  count         = var.enable_kro_capability ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  principal_arn = aws_iam_role.kro_capability[0].arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_capability.kro]
}

# AmazonEKSEditPolicy's rules are a fixed, AWS-enumerated list of API groups (apps,
# batch, networking.k8s.io, core resources, etc.) - it never included ACK's custom
# resource groups (iam.services.k8s.aws, s3.services.k8s.aws, ...) at all. kro
# orchestrates whatever CRD kinds an RGD's resources list references, so its RBAC has
# to cover every ACK service group any current or future RGD might use, not just the
# ones already hit (Policy, then Role, then Secret, ...). Same root cause and same
# unbounded whack-a-mole as the ArgoCD capability role's CSIDriver/ModelPackage/etc.
# errors - fixed the same way: a blanket grant instead of incremental per-kind ones.
# Unlike that case, aws_eks_access_policy_association applies directly to the
# principal_arn with no Kubernetes group/ClusterRoleBinding involved, so this isn't
# at risk of the same group-binding bug - no further Terraform pieces needed.
resource "aws_eks_access_policy_association" "kro_cluster_admin" {
  count         = var.enable_kro_capability ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_iam_role.kro_capability[0].arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_capability.kro]
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
