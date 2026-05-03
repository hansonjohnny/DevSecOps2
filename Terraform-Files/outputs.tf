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

output "jenkins_public_ip" {
  description = "Jenkins server public IP — access UI at http://<ip>:8080"
  value       = aws_instance.jenkins.public_ip
}

output "sonarqube_url" {
  description = "SonarQube URL — http://<jenkins_ip>:9000"
  value       = "http://${aws_instance.jenkins.public_ip}:9000"
}

output "jenkins_ssh" {
  description = "SSH command to connect to Jenkins server"
  value       = "ssh -i <your-key>.pem ec2-user@${aws_instance.jenkins.public_ip}"
}

output "ecr_backend_url" {
  description = "ECR backend repository URL — used to push and pull images"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR frontend repository URL — used to push and pull images"
  value       = aws_ecr_repository.frontend.repository_url
}