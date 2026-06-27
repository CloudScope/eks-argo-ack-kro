# IAM/Pod Identity prerequisites for External Secrets Operator (ESO). The operator
# itself is deployed via the ArgoCD GitOps repo (argocd_apps_repo_url), not here - this
# just makes sure the role is ready and waiting for the pods' service account before
# ArgoCD ever deploys them.

data "aws_caller_identity" "current" {}

locals {
  # Defaults to secrets named "<cluster_name>-*" so anything created under that
  # convention is covered without further IAM changes. Override with exact ARNs
  # once your actual secret names are known, to scope this down further.
  external_secrets_secret_arns = length(var.external_secrets_secret_arns) > 0 ? var.external_secrets_secret_arns : [
    "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}-*"
  ]
}

resource "aws_iam_role" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0
  name  = "${var.cluster_name}-external-secrets-role"

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
      Name = "${var.cluster_name}-external-secrets-role"
    }
  )
}

# Action list per https://external-secrets.io/latest/provider/aws-secrets-manager/ -
# read actions scoped to local.external_secrets_secret_arns; ListSecrets is a list
# operation that AWS IAM doesn't support resource-level scoping for, so it's granted
# separately with Resource = "*" (it still only returns metadata, not secret values).
resource "aws_iam_policy" "external_secrets_secretsmanager" {
  count       = var.enable_external_secrets ? 1 : 0
  name        = "${var.cluster_name}-external-secrets-secretsmanager"
  description = "Allows External Secrets Operator to read secrets from AWS Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadScopedSecretValues"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:BatchGetSecretValue",
          "secretsmanager:GetResourcePolicy"
        ]
        Resource = local.external_secrets_secret_arns
      },
      {
        Sid      = "ListSecretsMetadata"
        Effect   = "Allow"
        Action   = ["secretsmanager:ListSecrets"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets_secretsmanager" {
  count      = var.enable_external_secrets ? 1 : 0
  policy_arn = aws_iam_policy.external_secrets_secretsmanager[0].arn
  role       = aws_iam_role.external_secrets[0].name
}

# Matches the External Secrets Helm chart's default namespace/ServiceAccount name.
# If the chart values in the GitOps repo override either, update these to match.
resource "aws_eks_pod_identity_association" "external_secrets" {
  count           = var.enable_external_secrets ? 1 : 0
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets[0].arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
