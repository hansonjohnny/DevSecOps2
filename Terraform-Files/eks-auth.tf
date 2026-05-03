# ─────────────────────────────────────────
# EKS AUTH — aws-auth ConfigMap
# maps IAM roles to Kubernetes users
# ─────────────────────────────────────────
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      # EKS worker nodes
      {
        rolearn  = aws_iam_role.eks_nodes.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      # Jenkins EC2 — full cluster admin
      {
        rolearn  = aws_iam_role.jenkins_ec2.arn
        username = "jenkins"
        groups   = ["system:masters"]
      }
    ])
  }

  force = true

  depends_on = [aws_eks_cluster.main]
}