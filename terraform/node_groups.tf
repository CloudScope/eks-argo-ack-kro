# Shared launch template - this is how a custom security group gets attached to
# managed node group instances; aws_eks_node_group has no vpc_config/security_groups
# argument of its own. Disk size also moves here since EKS rejects disk_size on the
# node group once a launch_template is set.
resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"

  network_interfaces {
    security_groups = [aws_security_group.node.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 50
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.common_tags,
      {
        Name = "${var.cluster_name}-node"
      }
    )
  }

  tags = var.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# On-Demand Node Group (2 nodes)
resource "aws_eks_node_group" "on_demand" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-on-demand-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = var.on_demand_instance_types
  capacity_type  = "ON_DEMAND"
  ami_type       = var.node_ami_type

  scaling_config {
    desired_size = var.on_demand_desired_size
    max_size     = var.on_demand_desired_size
    min_size     = var.on_demand_desired_size
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = {
    Environment = var.environment
    NodeType    = "OnDemand"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-on-demand-ng"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Spot Node Group (3 nodes)
resource "aws_eks_node_group" "spot" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-spot-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = var.spot_instance_types
  capacity_type  = "SPOT"
  ami_type       = var.node_ami_type

  scaling_config {
    desired_size = var.spot_desired_size
    max_size     = var.spot_desired_size
    min_size     = var.spot_desired_size
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = {
    Environment = var.environment
    NodeType    = "Spot"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-spot-ng"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group Tags for On-Demand nodes
resource "aws_autoscaling_group_tag" "on_demand_cluster" {
  for_each = toset(
    data.aws_autoscaling_groups.on_demand.names
  )

  autoscaling_group_name = each.value

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "on_demand_enabled" {
  for_each = toset(
    data.aws_autoscaling_groups.on_demand.names
  )

  autoscaling_group_name = each.value

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

# Auto Scaling Group Tags for Spot nodes
resource "aws_autoscaling_group_tag" "spot_cluster" {
  for_each = toset(
    data.aws_autoscaling_groups.spot.names
  )

  autoscaling_group_name = each.value

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "spot_enabled" {
  for_each = toset(
    data.aws_autoscaling_groups.spot.names
  )

  autoscaling_group_name = each.value

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

# Data source to get ASG names
data "aws_autoscaling_groups" "on_demand" {
  filter {
    name   = "tag:eks:nodegroup-name"
    values = [aws_eks_node_group.on_demand.node_group_name]
  }
}

data "aws_autoscaling_groups" "spot" {
  filter {
    name   = "tag:eks:nodegroup-name"
    values = [aws_eks_node_group.spot.node_group_name]
  }
}
