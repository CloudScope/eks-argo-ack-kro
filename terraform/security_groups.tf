# Cluster and node security groups reference each other's IDs (cluster <-> node
# traffic both ways). Rules are managed as standalone aws_vpc_security_group_*_rule
# resources rather than inline ingress/egress blocks - mixing the two on a security
# group that other rules reference would also risk a dependency cycle between the
# two groups, since each would need the other's id before it exists.

# Cluster Security Group
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "cluster_https_from_vpc" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4          = aws_vpc.main.cidr_block
  from_port          = 443
  to_port             = 443
  ip_protocol        = "tcp"
  description         = "Allow HTTPS from VPC"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_node" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Allow nodes to communicate with cluster"
}

resource "aws_vpc_security_group_egress_rule" "cluster_all_outbound" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
  description         = "Allow all outbound traffic"
}

# Node Security Group
resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-node-sg"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Allow kubelet API from cluster control plane"
}

resource "aws_vpc_security_group_ingress_rule" "node_https_from_vpc" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4          = aws_vpc.main.cidr_block
  from_port          = 443
  to_port             = 443
  ip_protocol        = "tcp"
  description         = "Allow HTTPS within VPC"
}

resource "aws_vpc_security_group_ingress_rule" "node_dns_from_vpc" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4          = aws_vpc.main.cidr_block
  from_port          = 53
  to_port             = 53
  ip_protocol        = "udp"
  description         = "Allow DNS from VPC"
}

resource "aws_vpc_security_group_ingress_rule" "node_self" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Allow pod-to-pod communication"
}

resource "aws_vpc_security_group_egress_rule" "node_all_outbound" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
  description         = "Allow all outbound traffic"
}
