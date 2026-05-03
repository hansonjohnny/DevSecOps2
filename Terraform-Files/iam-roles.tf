#─────────────────────────────────────────
# IAM ROLE — JENKINS EC2
# assumed by the Jenkins EC2 instance
# allows Jenkins to push to ECR and manage EKS
# ─────────────────────────────────────────
resource "aws_iam_role" "jenkins_ec2" {
  name = "${var.project_name}-jenkins-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-jenkins-ec2-role"
    Environment = var.environment
  }
}

resource "aws_iam_instance_profile" "jenkins_ec2" {
  name = "${var.project_name}-jenkins-instance-profile"
  role = aws_iam_role.jenkins_ec2.name
}

# ─────────────────────────────────────────
# IAM ROLE — EKS CLUSTER CONTROL PLANE
# assumed by the EKS service itself
# ─────────────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-eks-cluster-role"
    Environment = var.environment
  }
}


# ─────────────────────────────────────────
# IAM ROLE — EKS WORKER NODES
# assumed by EC2 instances in the node group
# ─────────────────────────────────────────
resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-eks-node-role"
    Environment = var.environment
  }
}