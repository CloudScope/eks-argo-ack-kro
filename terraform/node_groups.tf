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

# Auto Scaling Group Tags. Each EKS managed node group always creates exactly one
# ASG, exposed directly on the node group resource - no for_each needed (and a
# for_each here would fail anyway: the ASG name is unknown until the node group is
# created in this same apply, and for_each requires its keys to be known at plan time).
resource "aws_autoscaling_group_tag" "on_demand_cluster" {
  autoscaling_group_name = aws_eks_node_group.on_demand.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "on_demand_enabled" {
  autoscaling_group_name = aws_eks_node_group.on_demand.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "spot_cluster" {
  autoscaling_group_name = aws_eks_node_group.spot.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "spot_enabled" {
  autoscaling_group_name = aws_eks_node_group.spot.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}
