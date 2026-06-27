# Re-adds the kubernetes provider (removed earlier when nothing used it) to manage
# ArgoCD's own Application CRD directly on the cluster - this is how "ArgoCD manages
# itself" gets bootstrapped: one root Application pointing at a git repo, after which
# everything else declared in that repo (including future ArgoCD config changes)
# syncs via GitOps instead of further Terraform changes here.
# (required_providers for "kubernetes" lives in main.tf - a module can only have one
# required_providers block, even across files, so it can't be redeclared here.)

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.name
}

# argocd_apps_repo_url is a private GitHub repo. Per AWS's "Username and token
# authentication" pattern (docs.aws.amazon.com/eks/latest/userguide/argocd-configure-repositories.html),
# credentials live in Secrets Manager (rotatable without touching the cluster) and the
# ArgoCD capability role is granted read access to just this one secret. The Kubernetes
# Repository Secret below references the Secrets Manager ARN, not the credentials
# directly - ArgoCD resolves the actual username/token from Secrets Manager at sync time.
resource "aws_secretsmanager_secret" "argocd_repo" {
  count = var.enable_argocd_capability ? 1 : 0
  name  = "${var.cluster_name}-argocd-repo-creds"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-argocd-repo-creds"
    }
  )
}

resource "aws_secretsmanager_secret_version" "argocd_repo" {
  count     = var.enable_argocd_capability ? 1 : 0
  secret_id = aws_secretsmanager_secret.argocd_repo[0].id
  secret_string = jsonencode({
    username = var.github_repo_username
    token    = var.github_repo_token
  })
}

resource "aws_iam_policy" "argocd_repo_secret" {
  count       = var.enable_argocd_capability ? 1 : 0
  name        = "${var.cluster_name}-argocd-repo-secret-read"
  description = "Allows the ArgoCD capability to read the private repo's Git credentials from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = aws_secretsmanager_secret.argocd_repo[0].arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "argocd_repo_secret" {
  count      = var.enable_argocd_capability ? 1 : 0
  policy_arn = aws_iam_policy.argocd_repo_secret[0].arn
  role       = aws_iam_role.argocd_capability[0].name
}

resource "kubernetes_secret_v1" "argocd_repo" {
  count = var.enable_argocd_capability ? 1 : 0

  metadata {
    name      = "argo-app-of-apps-repo"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type      = "git"
    url       = var.argocd_apps_repo_url
    secretArn = aws_secretsmanager_secret.argocd_repo[0].arn
  }

  depends_on = [aws_eks_capability.argocd]
}

# The IAM principal running `terraform apply` needs Kubernetes RBAC access to create
# this Application. EKS automatically grants the principal that created the cluster
# system:masters-equivalent access, so this works as long as the same principal (e.g.
# the GitHub Actions role) has run every apply against this cluster. If a different
# principal applies this, it will fail with 403/Unauthorized until that principal also
# gets an aws_eks_access_entry with sufficient permissions on the "argocd" namespace.
resource "kubernetes_manifest" "argocd_app_of_apps" {
  count = var.enable_argocd_capability ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "app-of-apps"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.argocd_apps_repo_url
        targetRevision = var.argocd_apps_repo_revision
        path           = var.argocd_apps_repo_path
        directory = {
          recurse = true
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }

  depends_on = [aws_eks_capability.argocd, kubernetes_secret_v1.argocd_repo]
}
