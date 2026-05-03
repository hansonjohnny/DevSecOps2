variable "project_name" {
  description = "Name of the project, used as prefix for all resources"
  type        = string
  default     = "todo-app"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.small"
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "c7i-flex.large"
}

variable "jenkins_ssh_cidr" {
  description = "CIDR block allowed to SSH into Jenkins — restrict to your IP e.g. 105.x.x.x/32"
  type        = string
  default     = "0.0.0.0/0"
}
