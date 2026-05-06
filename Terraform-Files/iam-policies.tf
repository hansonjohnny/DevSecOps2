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

# ─────────────────────────────────────────
# POLICY ATTACHMENTS — EKS CLUSTER ROLE
# ─────────────────────────────────────────

# allows EKS to manage AWS resources on your behalf
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─────────────────────────────────────────
# POLICY ATTACHMENTS — EKS NODE ROLE
# ─────────────────────────────────────────

# allows nodes to connect to the EKS cluster
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# allows the CNI plugin to manage pod networking (assign IPs to pods)
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# allows nodes to pull Docker images from ECR
resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# allows EBS CSI driver to provision volumes for pods
resource "aws_iam_role_policy_attachment" "eks_ebs_csi" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ─────────────────────────────────────────
# IAM POLICY FOR ALB CONTROLLER
# ─────────────────────────────────────────
resource "aws_iam_policy" "alb_controller" {
  name        = "${var.project_name}-alb-controller-policy"
  description = "Policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/alb-iam-policy.json")
}

# ─────────────────────────────────────────
# ATTACH POLICY TO ROLE
# ─────────────────────────────────────────
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}