# ─────────────────────────────────────────
# EKS CLUSTER
# ─────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true # flip to false after kubectl is configured
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
  }
}


# ─────────────────────────────────────────
# EKS NODE GROUP
# ─────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]

  tags = {
    Name        = "${var.project_name}-node-group"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# KUBERNETES NAMESPACE
# ─────────────────────────────────────────
resource "kubernetes_namespace" "todo_app" {
  metadata {
    name = "todo-app"

    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main    # ← wait for nodes too, not just the cluster
  ]
}


# ─────────────────────────────────────────
# DATA SOURCE — OIDC TLS CERTIFICATE
# fetches thumbprint for the OIDC provider
# defined in iam-roles.tf
# ─────────────────────────────────────────
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
