output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_eip" {
  description = "Elastic IP address of NAT Gateway"
  value       = aws_eip.nat.public_ip
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "public_subnets_cidr_blocks" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "private_subnets_cidr_blocks" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

output "public_route_table_id" {
  description = "Public Route Table ID"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private Route Table ID"
  value       = aws_route_table.private.id
}

# --- EKS cluster ---

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL (provisioned by default, unused while Pod Identity is the only IAM mechanism here)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "on_demand_node_group_id" {
  description = "On-demand node group ID"
  value       = aws_eks_node_group.on_demand.id
}

output "spot_node_group_id" {
  description = "Spot node group ID"
  value       = aws_eks_node_group.spot.id
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "EKS node security group ID"
  value       = aws_security_group.node.id
}

output "cluster_role_arn" {
  description = "EKS cluster IAM role ARN"
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "EKS node IAM role ARN"
  value       = aws_iam_role.node.arn
}

output "ack_capability_role_arn" {
  description = "ACK capability IAM role ARN"
  value       = var.enable_ack_capability ? aws_iam_role.ack_capability[0].arn : null
}

output "kro_capability_role_arn" {
  description = "KRO capability IAM role ARN"
  value       = var.enable_kro_capability ? aws_iam_role.kro_capability[0].arn : null
}

output "argocd_capability_role_arn" {
  description = "ArgoCD capability IAM role ARN"
  value       = var.enable_argocd_capability ? aws_iam_role.argocd_capability[0].arn : null
}

output "vpc_cni_role_arn" {
  description = "VPC CNI IAM role ARN"
  value       = var.enable_vpc_cni ? aws_iam_role.vpc_cni[0].arn : null
}

output "pod_identity_agent_addon_status" {
  description = "EKS Pod Identity Agent addon status"
  value       = var.enable_pod_identity ? aws_eks_addon.pod_identity_agent[0].status : null
}

output "configure_kubectl_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
