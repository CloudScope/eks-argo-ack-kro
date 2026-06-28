# Re-adds the kubernetes provider (removed earlier when nothing used it) to manage
# ArgoCD's own Application CRD directly on the cluster - this is how "ArgoCD manages
# itself" gets bootstrapped: one root Application pointing at a git repo, after which
# everything else declared in that repo (including future ArgoCD config changes)
# syncs via GitOps instead of further Terraform changes here.
# (required_providers for "kubernetes" lives in main.tf - a module can only have one
# required_providers block, even across files, so it can't be redeclared here.)

# Uses `exec` (shells out to `aws eks get-token` at the moment of each API call)
# instead of a statically-fetched data.aws_eks_cluster_auth token. That token is only
# valid ~15 minutes; with node groups, capabilities, and time_sleep waits ahead of this
# in the dependency graph, a long apply can easily outlive a token fetched once near
# the start, causing "Unauthorized" errors here even though the config is correct.
# Requires the AWS CLI to be present wherever `terraform apply` runs (already true on
# GitHub-hosted Actions runners, using whatever credentials configure-aws-credentials set up).
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", var.aws_region]
  }
}

# argocd_apps_repo_url is a private GitHub repo. Per AWS's "Username and token
# authentication" pattern (docs.aws.amazon.com/eks/latest/userguide/argocd-configure-repositories.html),
# credentials live in Secrets Manager (rotatable without touching the cluster) and the
# ArgoCD capability role is granted read access to just this one secret. The Kubernetes
# Repository Secret below references the Secrets Manager ARN, not the credentials
# directly - ArgoCD resolves the actual username/token from Secrets Manager at sync time.
#
# Terraform only looks up this secret by name - it never creates or holds the actual
# GitHub PAT, in Terraform state, tfvars, or CI secrets. Create/update it yourself with:
#   aws secretsmanager put-secret-value \
#     --secret-id "GIT_HUB_PAT" \
#     --secret-string '{"username":"<github-username>","token":"<github-pat>"}'
# The JSON keys MUST be exactly "username" and "token" - the ArgoCD capability's own
# secretArn parsing expects those names specifically and isn't configurable here.
data "aws_secretsmanager_secret" "argocd_repo" {
  count = var.enable_argocd_capability ? 1 : 0
  name  = "GIT_HUB_PAT"
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
        Resource = data.aws_secretsmanager_secret.argocd_repo[0].arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "argocd_repo_secret" {
  count      = var.enable_argocd_capability ? 1 : 0
  policy_arn = aws_iam_policy.argocd_repo_secret[0].arn
  role       = aws_iam_role.argocd_capability[0].name
}

# A repo-creds *template* (not a per-repo Repository secret) scoped to the
# https://github.com/CloudScope URL prefix - one GIT_HUB_PAT secret authenticates
# ArgoCD to every repo under that org, including argo_apps_repo_url and
# argocd_self_managed_repo_url today, and any future CloudScope repo without
# further Terraform changes. See:
# https://argo-cd.readthedocs.io/en/stable/operator-manual/argocd-repo-creds-yaml/
resource "kubernetes_secret_v1" "argocd_github_org_creds" {
  count = var.enable_argocd_capability ? 1 : 0

  metadata {
    name      = "cloudscope-org-repo-creds"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type      = "git"
    url       = "https://github.com/CloudScope"
    secretArn = data.aws_secretsmanager_secret.argocd_repo[0].arn
  }

  depends_on = [aws_eks_capability.argocd]
}

# The ArgoCD capability does NOT auto-register the cluster it runs on - per
# docs.aws.amazon.com/eks/latest/userguide/argocd-register-clusters.html, Applications
# can't sync anywhere until at least one cluster is explicitly registered. This secret
# holds no live credentials (just the EKS cluster ARN, a name, and a project) - actual
# auth flows through the IAM access entry the capability already has, so unlike the
# repo-creds secret above, this is safe to manage declaratively rather than running
# `argocd cluster add` by hand. Note the "server" field must be the cluster ARN, not
# the usual https://kubernetes.default.svc - that's explicitly unsupported here.
resource "kubernetes_secret_v1" "argocd_local_cluster" {
  count = var.enable_argocd_capability ? 1 : 0

  metadata {
    name      = "local-cluster"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }

  data = {
    name    = "local-cluster"
    server  = aws_eks_cluster.main.arn
    project = "default"
  }

  depends_on = [aws_eks_capability.argocd]
}

# Registering the cluster creates an access entry automatically, but with NO
# kubernetes_groups set - "eks-access-entry:<arn>" is a naming CONVENTION AWS's docs
# use when you explicitly assign a group yourself, not a group every access entry
# automatically belongs to. Bringing it under Terraform management to set an explicit
# group is what actually makes any ClusterRoleBinding/RoleBinding take effect.
#
# Defined once here (rather than reading kubernetes_groups back off the resource,
# which is a set and can't be indexed) and reused below for the ClusterRoleBinding subject.
locals {
  argocd_capability_group = "argocd-capability"
}

# EKS auto-creates this entry as a side effect of creating the ArgoCD capability
# itself, outside of Terraform - so this resource needs a clean slate to create
# against, or it hits a "ResourceInUseException". Deleted manually once via:
#   aws eks delete-access-entry --cluster-name smart-infra-manager-eks \
#     --principal-arn arn:aws:iam::085960855786:role/smart-infra-manager-eks-argocd-capability-role
# (an alternative to `terraform import`, with a brief auth gap for this principal
# between delete and the next apply - acceptable since access entries hold no data,
# Terraform just recreates the same logical entry with kubernetes_groups set correctly).
resource "aws_eks_access_entry" "argocd_capability" {
  count             = var.enable_argocd_capability ? 1 : 0
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.argocd_capability[0].arn
  kubernetes_groups = [local.argocd_capability_group]
  type              = "STANDARD"
}

# Namespace-scoped WRITE for where Applications actually deploy - "argocd" for now,
# since that's the only destination namespace declared below. This is an AWS-native
# access policy association, applied directly to the principal with no group/RBAC
# object needed, so it isn't affected by the group-binding bug above. Extend with
# another namespace-scoped association (same pattern) if/when repos target other
# namespaces.
resource "aws_eks_access_policy_association" "argocd_write_argocd_ns" {
  count         = var.enable_argocd_capability ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  principal_arn = aws_iam_role.argocd_capability[0].arn

  access_scope {
    type       = "namespace"
    namespaces = ["argocd"]
  }

  depends_on = [aws_eks_capability.argocd]
}

# Cluster-wide READ (for health checks/drift detection across any resource type, any
# API group - hence a custom wildcard ClusterRole rather than a built-in view policy,
# since no AWS access policy grants true */* read). This DOES need the explicit group
# above, bound via the ClusterRoleBinding below.
resource "kubernetes_cluster_role_v1" "argocd_read_all" {
  count = var.enable_argocd_capability ? 1 : 0

  metadata {
    name = "argocd-read-all"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [aws_eks_capability.argocd]
}

resource "kubernetes_cluster_role_binding_v1" "argocd_read_all" {
  count = var.enable_argocd_capability ? 1 : 0

  metadata {
    name = "argocd-read-all"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argocd_read_all[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = local.argocd_capability_group
    api_group = "rbac.authorization.k8s.io"
    # Explicitly empty: namespace is meaningless for Group/User subjects (only
    # ServiceAccount uses it) and per the Kubernetes API spec, a non-empty value here
    # on a non-namespaced kind can make the binding invalid. Without this, the provider
    # defaulted it to "default", which silently broke this binding from the start.
    namespace = ""
  }
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
        name      = "local-cluster"
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

  depends_on = [
    aws_eks_capability.argocd,
    kubernetes_secret_v1.argocd_github_org_creds,
    kubernetes_secret_v1.argocd_local_cluster,
    aws_eks_access_policy_association.argocd_write_argocd_ns,
    kubernetes_cluster_role_binding_v1.argocd_read_all,
  ]
}

# Second, independent Application watching cloudscope-argocd-self-managed - kept
# separate from app-of-apps rather than folded into it, per explicit instruction.
# Both repos are covered by the same org-wide credential template above.
resource "kubernetes_manifest" "argocd_self_managed" {
  count = var.enable_argocd_capability ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "argocd-self-managed"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.argocd_self_managed_repo_url
        targetRevision = var.argocd_self_managed_repo_revision
        path           = var.argocd_self_managed_repo_path
        directory = {
          recurse = true
        }
      }
      destination = {
        name      = "local-cluster"
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

  depends_on = [
    aws_eks_capability.argocd,
    kubernetes_secret_v1.argocd_github_org_creds,
    kubernetes_secret_v1.argocd_local_cluster,
    aws_eks_access_policy_association.argocd_write_argocd_ns,
    kubernetes_cluster_role_binding_v1.argocd_read_all,
  ]
}
