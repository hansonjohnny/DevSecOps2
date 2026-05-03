#!/bin/bash
exec > /var/log/user-data.log 2>&1

# ── Update System ─────────────────────────────────────
apt-get update -y
apt-get upgrade -y

# ── Java 21 ───────────────────────────────────────────
apt-get install -y fontconfig openjdk-21-jre openjdk-21-jdk

# ── Jenkins ───────────────────────────────────────────
mkdir -p /etc/apt/keyrings
wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y
apt-get install -y jenkins
systemctl enable jenkins
systemctl start jenkins

# ── Docker ────────────────────────────────────────────
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y $pkg 2>/dev/null || true
done
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker jenkins
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# ── SonarQube ─────────────────────────────────────────
docker run -d --name sonar -p 9000:9000 sonarqube:lts-community

# ── AWS CLI ───────────────────────────────────────────
apt-get install -y unzip curl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -o /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update
rm -rf /tmp/awscliv2.zip /tmp/aws/

# ── kubectl ───────────────────────────────────────────
KUBECTL_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# ── eksctl ────────────────────────────────────────────
curl --silent --location \
  "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
  | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin/

# ── Terraform ─────────────────────────────────────────
apt-get install -y gnupg software-properties-common lsb-release
wget -O- https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com noble main" \
  | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update -y
apt-get install -y terraform

# ── Trivy ─────────────────────────────────────────────
apt-get install -y apt-transport-https gnupg wget
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor \
  | tee /usr/share/keyrings/trivy-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy-keyring.gpg] https://aquasecurity.github.io/trivy-repo/deb noble main" \
  | tee /etc/apt/sources.list.d/trivy.list
apt-get update -y
apt-get install -y trivy

# ── Helm ──────────────────────────────────────────────
snap install helm --classic

echo "=== Installation complete ===" >> /var/log/user-data.log