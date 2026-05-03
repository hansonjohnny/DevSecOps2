# ─────────────────────────────────────────
# EC2 INSTANCE — JENKINS SERVER
# installs: Java, Jenkins, Docker,
# Trivy, SonarQube, AWS CLI, kubectl
# ─────────────────────────────────────────
resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ami.id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  key_name                    = data.aws_key_pair.jenkins-key.key_name
  iam_instance_profile        = aws_iam_instance_profile.jenkins_ec2.name
  associate_public_ip_address = true


  root_block_device {
    volume_size           = 30 # GB — enough for Docker images and build artifacts
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # user_data runs once on first boot
  # installs all tools Jenkins needs
  user_data = templatefile("./tools-install.sh", {})

  tags = {
    Name        = "${var.project_name}-jenkins-server"
    Environment = var.environment
  }
}

resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-jenkins-eip"
    Environment = var.environment
  }
}
