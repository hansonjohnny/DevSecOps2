output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS, RDS, Redis)"
  value       = aws_subnet.private[*].id
}

output "ecr_backend_url" {
  description = "ECR backend repository URL — used to push and pull images"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR frontend repository URL — used to push and pull images"
  value       = aws_ecr_repository.frontend.repository_url
}

output "jenkins_public_ip" {
  description = "Jenkins server public IP"
  value       = aws_eip.jenkins.public_ip
}

output "sonarqube_url" {
  description = "SonarQube URL"
  value       = "http://${aws_eip.jenkins.public_ip}:9000"
}

output "jenkins_ssh" {
  description = "SSH command"
  value       = "ssh -i <your-key>.pem ubuntu@${aws_eip.jenkins.public_ip}"
}