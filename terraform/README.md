# EKS + VPC Terraform Configuration

This Terraform configuration creates a production-ready VPC and an EKS 1.36 cluster (ArgoCD/ACK/kro capabilities, Pod Identity, AWS VPC CNI, 2 on-demand + 3 spot nodes) in a single state.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/16)                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────┐                ┌─────────────────┐ │
│  │ Public Subnets  │                │ Private Subnets │ │
│  ├─────────────────┤                ├─────────────────┤ │
│  │ 10.0.1.0/24     │                │ 10.0.11.0/24    │ │
│  │ 10.0.2.0/24     │                │ 10.0.12.0/24    │ │
│  │ 10.0.3.0/24     │                │ 10.0.13.0/24    │ │
│  └─────────────────┘                └─────────────────┘ │
│         ▲                                     │          │
│         │                                     │          │
│    [IGW]├─────────────────────┐      [NAT GW]│          │
│         │                     │                │          │
│         └─────────────────────┤────────────────┘          │
│                               │                          │
│                          [Route Tables]                  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Resources Created

### Network Components
- **VPC**: 10.0.0.0/16 with DNS hostnames and DNS support enabled
- **Internet Gateway**: For public subnet internet access
- **NAT Gateway**: For private subnet internet outbound access
- **Elastic IP**: For NAT Gateway

### Subnets (across 3 Availability Zones)
- **Public Subnets** (3):
  - 10.0.1.0/24 (AZ-1)
  - 10.0.2.0/24 (AZ-2)
  - 10.0.3.0/24 (AZ-3)

- **Private Subnets** (3):
  - 10.0.11.0/24 (AZ-1)
  - 10.0.12.0/24 (AZ-2)
  - 10.0.13.0/24 (AZ-3)

### Route Tables
- **Public Route Table**: Routes 0.0.0.0/0 → Internet Gateway
- **Private Route Table**: Routes 0.0.0.0/0 → NAT Gateway

## Tags Applied

All resources include the following tags for EKS compatibility:

### Default Tags (Applied to all resources)
- `CreatedBy`: terraform
- `Environment`: dev
- `Project`: eks-cluster

### EKS-Specific Tags

**Public Subnets:**
- `kubernetes.io/role/elb`: 1 (for ELB/ALB)
- `kubernetes.io/cluster/eks-cluster`: shared

**Private Subnets:**
- `kubernetes.io/role/internal-elb`: 1 (for internal ALB)
- `kubernetes.io/cluster/eks-cluster`: shared

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- AWS Account with appropriate IAM permissions

## Usage

### 1. Initialize Terraform
```bash
cd terraform
terraform init
```

### 2. Review the Plan
```bash
terraform plan
```

### 3. Apply Configuration
```bash
terraform apply
```

### 4. Destroy (when needed)
```bash
terraform destroy
```

## Customization

### Update Variables

Modify `terraform.tfvars` to customize:

```hcl
aws_region           = "us-east-1"          # AWS region
environment          = "dev"                # Environment name
project_name         = "eks-cluster"        # Project name
vpc_cidr             = "10.0.0.0/16"        # VPC CIDR
public_subnet_cidrs  = [...]                # Public subnet CIDRs
private_subnet_cidrs = [...]                # Private subnet CIDRs
```

### Change Project Name for EKS Tags

Update `project_name` to match your EKS cluster name for proper tag integration:

```hcl
project_name = "my-eks-cluster"
```

This updates the EKS tags to: `kubernetes.io/cluster/my-eks-cluster`

## Outputs

The configuration provides the following outputs:

```bash
terraform output
```

**Key Outputs:**
- `vpc_id`: VPC identifier
- `public_subnets`: List of public subnet IDs
- `private_subnets`: List of private subnet IDs
- `nat_gateway_eip`: NAT Gateway public IP
- Route table IDs for manual associations if needed

## EKS Integration

These tags are required for EKS service discovery and load balancer provisioning:

1. **ELB/ALB in Public Subnets**: Requires `kubernetes.io/role/elb: 1`
2. **Internal ALB in Private Subnets**: Requires `kubernetes.io/role/internal-elb: 1`
3. **Cluster Discovery**: Requires `kubernetes.io/cluster/<cluster-name>: shared`

When creating your EKS cluster, use the same `project_name` value for automatic tag compatibility.

## Best Practices Implemented

✅ Multi-AZ deployment for high availability
✅ Separate public and private subnets
✅ NAT Gateway for secure private subnet internet access
✅ Proper EKS tagging for load balancer provisioning
✅ DNS support enabled for container networking
✅ Map public IP on launch for public subnets
✅ Default tags for cost tracking and resource management
✅ Terraform-managed infrastructure
✅ Modular and reusable configuration

## Security Considerations

- Private subnets do not have direct internet access (only through NAT)
- NAT Gateway provides outbound internet access for private subnets
- Public subnets are isolated from private subnets via route tables
- Consider adding security groups and NACLs based on your requirements

## Files Structure

```
terraform/
├── main.tf              # VPC, subnets, route tables, NAT (existing)
├── iam.tf               # EKS cluster/node IAM roles
├── security_groups.tf   # EKS cluster/node security groups
├── eks_cluster.tf        # EKS cluster, pod identity agent, vpc-cni/coredns/kube-proxy addons
├── node_groups.tf        # Launch template, on-demand + spot managed node groups, ASG tags
├── capabilities.tf       # ACK / kro / ArgoCD EKS Capabilities + ACK access entry
├── variables.tf          # Input variables (VPC + EKS)
├── outputs.tf             # Output values (VPC + EKS)
├── backend.tf             # S3 state backend
└── terraform.tfvars       # Variable values
```

## EKS Cluster

The cluster is created in the same VPC/subnets defined in `main.tf` (no `existing_vpc_id` lookups -
direct resource references, e.g. `aws_subnet.private[*].id`). Key points:

- **Kubernetes 1.36**, control plane logging enabled, access mode `API_AND_CONFIG_MAP`.
- **Nodes**: 2 on-demand + 3 spot (fixed size, capped at 5 total), Graviton (arm64) `t4g.large`/`m6g.large` family, in private subnets, each EKS managed node group backed by its own Auto Scaling Group. Container images must support `arm64` (build multi-arch images, or use `arm64`-native ones).
- **Pod Identity**: `eks-pod-identity-agent` addon + a Pod Identity association for the VPC CNI's `aws-node` service account (no IRSA/OIDC).
- **Capabilities**: ACK, kro, and ArgoCD enabled via the native `aws_eks_capability` resource (AWS-managed, no Helm install required).

```bash
terraform init
terraform plan
terraform apply

aws eks update-kubeconfig --region ap-south-1 --name smart-infra-manager-eks
kubectl get nodes
```

## Troubleshooting

### NAT Gateway not accessible
- Ensure Elastic IP is associated correctly
- Verify route table associations
- Check security groups on instances in private subnets

### Subnets not spanning AZs correctly
- Verify available AZs in your region
- Check `data.aws_availability_zones.available` in `main.tf`

### EKS integration issues
- Ensure `project_name` in `terraform.tfvars` matches your EKS cluster name
- Verify all tags are correctly applied with `aws ec2 describe-subnets`

## Support

For EKS-specific documentation, refer to:
- [AWS EKS VPC Requirements](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
