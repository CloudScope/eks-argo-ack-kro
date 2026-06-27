variable "aws_region" {
  description = "AWS region for the resources"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "smart-infra-manager"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "created_by" {
  description = "Created by tag"
  type        = string
  default     = "terraform"
}

variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Purpose   = "EKS"
    GitRepo   = "https://github.com/CloudScope/eks-argo-ack-kro"
  }
}

# --- EKS cluster ---

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "smart-infra-manager-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.36"
}

variable "on_demand_desired_size" {
  description = "Number of on-demand (dedicated) nodes"
  type        = number
  default     = 2
}

variable "spot_desired_size" {
  description = "Number of spot nodes"
  type        = number
  default     = 3
}

variable "on_demand_instance_types" {
  description = "Graviton (arm64) EC2 instance types for on-demand worker nodes. Must stay arm64-only - EKS node groups can't mix CPU architectures."
  type        = list(string)
  default     = ["t4g.large", "m6g.large"]
}

variable "spot_instance_types" {
  description = "Graviton (arm64) EC2 instance types for spot worker nodes. Kept to the same vCPU/memory size (2 vCPU / 8 GiB) across families, per AWS guidance, so cluster-autoscaler scaling stays predictable and the price-capacity-optimized allocation strategy has more capacity pools to choose from, which reduces interruption frequency. Only includes types confirmed available in ap-south-1 - verify region availability before adding more (m6gn.large/m7g.large failed with Ec2InstanceTypeDoesNotExist here)."
  type        = list(string)
  default     = ["t4g.large", "m6g.large"]
}

variable "node_ami_type" {
  description = "EKS-optimized AMI type for worker nodes. AL2023_ARM_64_STANDARD matches the Graviton instance types above; change this too if you ever go back to x86_64."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "enable_pod_identity" {
  description = "Enable EKS Pod Identity"
  type        = bool
  default     = true
}

variable "argocd_admin_group_name" {
  description = "Display name of the AWS IAM Identity Center group created and mapped to ArgoCD's ADMIN role."
  type        = string
  default     = "ARGOCD_ADMIN"
}

variable "enable_ack_capability" {
  description = "Enable ACK capability"
  type        = bool
  default     = true
}

variable "enable_kro_capability" {
  description = "Enable KRO capability"
  type        = bool
  default     = true
}

variable "enable_argocd_capability" {
  description = "Enable ArgoCD capability"
  type        = bool
  default     = true
}

variable "enable_vpc_cni" {
  description = "Enable AWS VPC CNI"
  type        = bool
  default     = true
}

# --- ArgoCD self-management (app-of-apps) ---

variable "argocd_apps_repo_url" {
  description = "Git repo ArgoCD watches as its app-of-apps source of truth"
  type        = string
  default     = "https://github.com/CloudScope/argo-app-of-apps"
}

variable "argocd_apps_repo_revision" {
  description = "Git revision (branch/tag) of argocd_apps_repo_url to track"
  type        = string
  default     = "main"
}

variable "argocd_apps_repo_path" {
  description = "Path within argocd_apps_repo_url containing the Application/AppProject manifests"
  type        = string
  default     = "."
}

variable "github_repo_username" {
  description = "GitHub username for ArgoCD to authenticate to the private argocd_apps_repo_url repo (personal access token auth). Generate a token at github.com/settings/tokens with read-only repo access."
  type        = string
  sensitive   = true
}

variable "github_repo_token" {
  description = "GitHub personal access token (read-only repo scope) for ArgoCD to authenticate to the private argocd_apps_repo_url repo"
  type        = string
  sensitive   = true
}

# --- External Secrets Operator ---

variable "enable_external_secrets" {
  description = "Create the IAM role and Pod Identity association for External Secrets Operator (the operator itself is deployed via the ArgoCD GitOps repo, not Terraform)"
  type        = bool
  default     = true
}

variable "external_secrets_secret_arns" {
  description = "Secrets Manager secret ARN patterns External Secrets Operator is allowed to read. Leave empty to default to a prefix matching this cluster's naming convention (\"<cluster_name>-*\"); override with exact ARNs once your real secret names are known."
  type        = list(string)
  default     = []
}
