# ─────────────────────────────────────────
# POLICY ATTACHMENTS — JENKINS EC2 ROLE
# ─────────────────────────────────────────

# allows Jenkins to push/pull images from ECR
resource "aws_iam_role_policy_attachment" "jenkins_ecr" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# allows Jenkins to interact with EKS cluster
resource "aws_iam_role_policy_attachment" "jenkins_eks" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# allows Jenkins to describe and manage EKS cluster
resource "aws_iam_role_policy" "jenkins_eks_full" {
  name = "${var.project_name}-jenkins-eks-policy"
  role = aws_iam_role.jenkins_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:AccessKubernetesApi",
          "eks:UpdateClusterConfig",
          "sts:AssumeRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# allows Jenkins to manage EKS addons
resource "aws_iam_role_policy" "jenkins_eks_addons" {
  name = "${var.project_name}-jenkins-eks-addons"
  role = aws_iam_role.jenkins_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "eks:CreateAddon",
        "eks:DescribeAddon",
        "eks:UpdateAddon",
        "eks:DeleteAddon",
        "eks:ListAddons"
      ]
      Resource = "*"
    }]
  })
}

# allows Jenkins to describe EC2 resources
resource "aws_iam_role_policy_attachment" "jenkins_ec2_readonly" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}