# Terraform Infrastructure — Todo App (Main Module)

This module provisions the complete AWS infrastructure for a three-tier containerised application. It runs **after** the [state bootstrap module](../bootstrap/README.md) and stores its state remotely in the S3 bucket and DynamoDB table created there.

The stack includes: a production-grade VPC, EKS cluster with managed node groups, Jenkins CI server with all tooling pre-installed, ECR image registries, ArgoCD for GitOps deployments, and an AWS Load Balancer Controller with TLS termination via ACM and Route 53.

---

## Architecture Overview

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  Route 53 (johnnycloudops.xyz)                                  │
│  ACM Certificate (TLS)                                          │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│  VPC  10.0.0.0/16          us-east-2                            │
│                                                                 │
│  ┌──────────────────┐   ┌──────────────────┐                   │
│  │  Public Subnet 1 │   │  Public Subnet 2 │  ← ALB, Jenkins   │
│  │  10.0.0.0/24     │   │  10.0.1.0/24     │    NAT GW EIPs    │
│  └────────┬─────────┘   └────────┬─────────┘                   │
│           │  NAT GW               │  NAT GW                     │
│  ┌────────▼─────────┐   ┌────────▼─────────┐                   │
│  │  Private Subnet 1│   │  Private Subnet 2│  ← EKS Nodes      │
│  │  10.0.10.0/24    │   │  10.0.11.0/24    │                   │
│  └──────────────────┘   └──────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘

EKS Cluster
├── Node Group (t3.small, 2 nodes, max 3)
│   ├── three-tier namespace  ← app pods (frontend, backend)
│   └── kube-system namespace ← ALB Controller, EBS CSI Driver
└── ArgoCD (argocd namespace) ← watches Git, deploys app

Jenkins EC2 (public subnet, m7i-flex.large)
├── Jenkins CI
├── Docker
├── SonarQube (container, port 9000)
├── Trivy (image scanner)
├── AWS CLI, kubectl, eksctl, Helm, Terraform
└── IAM Role → ECR push/pull, EKS admin, S3/DynamoDB state

ECR
├── todo-app/backend
└── todo-app/frontend
```

---

## File Structure

```
.
├── backend.tf          # Remote state configuration (S3 + DynamoDB)
├── providers.tf        # All provider declarations and configuration
├── variables.tf        # Input variables with defaults
├── outputs.tf          # Exported values after apply
├── gather.tf           # Data sources (AMI lookup, key pair)
├── vpc.tf              # VPC, subnets, IGW, NAT GWs, route tables
├── security-groups.tf  # All security groups and rules
├── iam-roles.tf        # IAM roles, OIDC provider, instance profiles
├── iam-policies.tf     # Policy attachments for all roles
├── ec2.tf              # Jenkins EC2 instance + EIP
├── ecr.tf              # ECR repositories + lifecycle policies
├── eks.tf              # EKS cluster, node group, launch template, addons
├── eks-auth.tf         # aws-auth ConfigMap (IAM → Kubernetes RBAC)
├── argocd.tf           # ArgoCD namespace + Helm install
├── alb-controller.tf   # ALB Controller service account + Helm install
├── dns.tf              # Route 53, ACM certificate, DNS validation
├── tools-install.sh    # EC2 user_data — installs all Jenkins tooling
└── alb-iam-policy.json # ALB Controller IAM policy (from AWS docs)
```

---

## File Reference

### `backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "cloud-native-buckettt"
    key            = "todo-app/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "cloud-native-dynamodb-lock"
  }
}
```

This wires the module to the remote state infrastructure created by the bootstrap module. Every `terraform apply` reads the current state from S3, acquires a lock in DynamoDB, makes changes, and releases the lock.

- **`key`** — the path within the bucket where this module's state file lives. Using a namespaced path (`todo-app/terraform.tfstate`) allows multiple modules to share the same bucket without collision.
- **`encrypt = true`** — instructs Terraform to use the bucket's AES-256 server-side encryption for the state file.
- **`dynamodb_table`** — the table must already exist before `terraform init` is run; this is why the bootstrap module must be applied first.

> **Important:** The `backend` block does not support interpolation (no `var.*` references). All values must be hardcoded literals.

---

### `providers.tf`

Declares five providers and configures three of them:

| Provider | Version | Purpose |
|---|---|---|
| `aws` | ~> 5.0 | All AWS resources |
| `tls` | ~> 4.0 | Fetching the EKS OIDC certificate thumbprint |
| `kubernetes` | ~> 2.0 | Managing in-cluster resources (namespaces, ConfigMaps, service accounts) |
| `helm` | ~> 2.0 | Installing Helm charts (ArgoCD, ALB Controller) |
| `time` | ~> 0.9 | Time-based resources (delays between resource creation) |

**Kubernetes and Helm provider authentication:**

Both providers authenticate to the EKS cluster dynamically using the `exec` block — they call `aws eks get-token` to generate a short-lived bearer token at runtime. This avoids storing credentials and works in CI without a pre-configured kubeconfig:

```hcl
exec {
  api_version = "client.authentication.k8s.io/v1beta1"
  args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
  command     = "aws"
}
```

This means the machine running `terraform apply` must have AWS credentials with `eks:DescribeCluster` access. The Jenkins EC2 instance satisfies this via its IAM instance profile.

---

### `variables.tf`

| Variable | Type | Default | Description |
|---|---|---|---|
| `project_name` | string | `todo-app` | Prefix applied to every resource name and tag |
| `environment` | string | `dev` | Environment tag (`dev`, `staging`, `prod`) |
| `aws_region` | string | `us-east-2` | AWS region for all resources |
| `eks_version` | string | `1.32` | Kubernetes control plane version |
| `node_instance_type` | string | `t3.small` | EC2 type for EKS worker nodes |
| `jenkins_instance_type` | string | `m7i-flex.large` | EC2 type for Jenkins server |
| `jenkins_ssh_cidr` | string | `0.0.0.0/0` | IP CIDR allowed to SSH and access Jenkins/SonarQube UIs |

> **Security note:** `jenkins_ssh_cidr` defaults to open. Before applying in any environment, restrict this to your actual IP: `terraform apply -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'`

---

### `outputs.tf`

After `terraform apply`, these values are printed and can be consumed by other modules or scripts:

| Output | Description |
|---|---|
| `vpc_id` | VPC ID — useful for peering or referencing in other modules |
| `public_subnet_ids` | Subnet IDs where the ALB and Jenkins live |
| `private_subnet_ids` | Subnet IDs for EKS nodes |
| `ecr_backend_url` | Full ECR URL for the backend image — used in `docker push` and Kubernetes manifests |
| `ecr_frontend_url` | Full ECR URL for the frontend image |
| `jenkins_public_ip` | Static EIP for Jenkins — use this for SSH and bookmarking |
| `sonarqube_url` | Constructed SonarQube URL (`http://<jenkins-ip>:9000`) |
| `jenkins_ssh` | Ready-to-run SSH command |
| `eks_cluster_name` | Cluster name — used in `aws eks update-kubeconfig` |
| `eks_cluster_endpoint` | API server endpoint — used by the Kubernetes/Helm providers |

---

### `gather.tf` — Data Sources

Data sources read existing AWS resources without managing them.

**AMI lookup:**
```hcl
data "aws_ami" "ami" {
  most_recent = true
  filter { name = "name"; values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] }
  filter { name = "virtualization-type"; values = ["hvm"] }
  owners = ["099720109477"]  # Canonical's official AWS account ID
}
```
This always resolves to the latest Ubuntu 24.04 LTS (Noble) AMI in the target region. Using `most_recent = true` with a version-pinned name pattern means you get security patches without manually updating an AMI ID.

**Key pair lookup:**
```hcl
data "aws_key_pair" "jenkins-key" {
  key_name = "jenkins-key"
}
```
The key pair must be created manually in the AWS console before applying. Terraform references it by name; the private key file (`.pem`) is kept locally for SSH access to Jenkins-server.

---

### `vpc.tf` — Networking

The VPC uses a `10.0.0.0/16` CIDR, giving 65,536 addresses. Resources are spread across two Availability Zones for high availability.

**Subnet layout:**

| Subnet | CIDR | AZ | Purpose |
|---|---|---|---|
| Public 1 | 10.0.0.0/24 | us-east-2a | ALB, Jenkins, NAT GW 1 |
| Public 2 | 10.0.1.0/24 | us-east-2b | NAT GW 2 |
| Private 1 | 10.0.10.0/24 | us-east-2a | EKS nodes (AZ-a) |
| Private 2 | 10.0.11.0/24 | us-east-2b | EKS nodes (AZ-b) |

CIDRs are computed with `cidrsubnet("10.0.0.0/16", 8, index)` — the `8` adds 8 bits to the prefix (making /24s), and `index` sets the third octet. Private subnets use `index + 10` to avoid overlap with public subnets.

**Kubernetes subnet tags** are required so the ALB Ingress Controller can discover which subnets to place load balancers in:
- Public subnets: `kubernetes.io/role/elb = 1` (internet-facing ALBs)
- Private subnets: `kubernetes.io/role/internal-elb = 1` (internal ALBs)

**Internet Gateway** — attached to the VPC; provides the public subnets with a route to `0.0.0.0/0`.

**NAT Gateways** — one per AZ, placed in public subnets. Private subnets route outbound internet traffic through their AZ-local NAT GW. This means if one AZ loses its NAT GW, the other AZ's nodes are unaffected. Each NAT GW has a static Elastic IP.

**Route tables:**
- One public route table shared by both public subnets → routes all traffic to the IGW.
- Two private route tables (one per AZ) → each routes outbound traffic to its local NAT GW, keeping traffic within the same AZ to avoid cross-AZ data transfer costs.

---

### `security-groups.tf` — Security Groups

Four security groups, each with a specific role and tightly scoped rules:

**ALB Security Group (`alb-sg`)**
- Inbound: TCP 80 and 443 from `0.0.0.0/0` (internet)
- Outbound: all traffic (forwards requests to pods)
- The only entry point from the internet into the cluster

**EKS Cluster Control Plane (`eks-cluster-sg`)**
- Inbound: TCP 443 from EKS nodes (so `kubectl` calls from nodes work)
- Inbound: TCP 443 from Jenkins (so the CI server can call the Kubernetes API)
- Outbound: all traffic
- These are added as separate `aws_security_group_rule` resources (not inline `ingress` blocks) because they reference other security groups by ID, creating an explicit dependency

**EKS Worker Nodes (`eks-nodes-sg`)**
- Inbound: all traffic from itself (`self = true`) — node-to-node and pod-to-pod communication
- Inbound: TCP 1025–65535 from control plane — kubelet, logs, exec, port-forward
- Inbound: TCP 80, 443, 5000 from ALB — forwards HTTP, HTTPS, and backend API traffic to pods
- Outbound: all traffic — pull images from ECR, call AWS APIs via NAT GW

**Jenkins EC2 (`jenkins-sg`)**
- Inbound: TCP 22 from `var.jenkins_ssh_cidr` — SSH
- Inbound: TCP 8080 from `var.jenkins_ssh_cidr` — Jenkins web UI
- Inbound: TCP 9000 from `var.jenkins_ssh_cidr` — SonarQube web UI
- Outbound: all traffic

Rules that reference other security groups (instead of CIDR blocks) automatically update if the referenced group's membership changes — more secure and maintainable than hardcoding IPs.

---

### `iam-roles.tf` — IAM Roles

Five IAM roles are created, each with a specific trust policy defining who can assume it:

**`jenkins-ec2-role`** — trusted by `ec2.amazonaws.com`
Assumed by the Jenkins EC2 instance via its instance profile. Grants Jenkins permissions to push/pull ECR images, manage the EKS cluster, read EC2 metadata, and access the Terraform state bucket.

**`eks-cluster-role`** — trusted by `eks.amazonaws.com`
Assumed by the EKS control plane. Required for EKS to manage AWS resources (load balancers, security groups) on your behalf.

**`eks-node-role`** — trusted by `ec2.amazonaws.com`
Assumed by EC2 worker nodes. Allows nodes to register with the cluster, pull images from ECR, and have pod networking configured by the CNI plugin.

**`ebs-csi-role`** — trusted by the EKS OIDC provider (IRSA)
Assumed by the EBS CSI controller service account inside Kubernetes. Uses IAM Roles for Service Accounts (IRSA): the OIDC condition pins the role to the exact Kubernetes service account (`kube-system:ebs-csi-controller-sa`), so only that pod can assume it.

**`alb-controller-role`** — trusted by the EKS OIDC provider (IRSA)
Same IRSA pattern, pinned to `kube-system:aws-load-balancer-controller`. Grants the ALB Controller permission to create and manage AWS load balancers in response to Kubernetes Ingress objects.

**OIDC Provider:**
```hcl
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```
The OIDC provider is the bridge between Kubernetes service accounts and AWS IAM. EKS issues OIDC tokens to pods; AWS STS validates these tokens against the registered OIDC provider and issues temporary IAM credentials. The TLS thumbprint is fetched dynamically via the `tls` provider to avoid hardcoding.

---

### `iam-policies.tf` — Policy Attachments

**Jenkins EC2 role receives:**

| Policy | Type | Purpose |
|---|---|---|
| `AmazonEC2ContainerRegistryFullAccess` | AWS managed | Push/pull all ECR repositories |
| `AmazonEKSClusterPolicy` | AWS managed | Describe and connect to EKS clusters |
| `jenkins-eks-policy` | Inline | `DescribeCluster`, `AccessKubernetesApi`, `AssumeRole` |
| `jenkins-eks-addons` | Inline | Manage EKS addons (create, update, delete) |
| `AmazonEC2ReadOnlyAccess` | AWS managed | Describe EC2 resources |
| `AmazonS3FullAccess` | AWS managed | Access S3 buckets (artifacts, cache) |
| `jenkins-terraform-state` | Inline | Scoped S3 + DynamoDB access for Terraform state operations only |

**EKS cluster role receives:**
- `AmazonEKSClusterPolicy` — required for the control plane to operate

**EKS node role receives:**

| Policy | Purpose |
|---|---|
| `AmazonEKSWorkerNodePolicy` | Register node with cluster |
| `AmazonEKS_CNI_Policy` | VPC CNI plugin assigns pod IPs from the subnet |
| `AmazonEC2ContainerRegistryReadOnly` | Pull images from ECR |
| `AmazonEBSCSIDriverPolicy` | EBS volume provisioning for PersistentVolumeClaims |

**ALB Controller role receives:**
- `alb-controller-policy` — loaded from `alb-iam-policy.json` (the official policy published by AWS, containing ~30 permissions for managing ALBs, target groups, listeners, and WAF rules)

---

### `ec2.tf` — Jenkins Server

```hcl
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ami.id
  instance_type          = var.jenkins_instance_type   # m7i-flex.large
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  key_name               = data.aws_key_pair.jenkins-key.key_name
  iam_instance_profile   = aws_iam_instance_profile.jenkins_ec2.name
  user_data              = templatefile("./tools-install.sh", {})

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }
}
```

- **`m7i-flex.large`** — 2 vCPU, 8 GB RAM. The `flex` variant of the M7i family offers competitive price/performance for bursty workloads like CI builds and Docker image operations.
- **30 GB gp3 root volume** — provides space for Docker layer cache, build artifacts, and Jenkins workspace. gp3 delivers 3,000 IOPS at no extra cost.
- **Encrypted root volume** — protects build artifacts and any credentials written to disk.
- **`user_data`** — runs `tools-install.sh` on first boot. The `templatefile()` function is used even without variables, keeping the pattern consistent for future variable injection.

**Elastic IP:**
A separate `aws_eip` resource is attached post-creation. This gives Jenkins a static public IP that persists across instance stops/starts, so bookmarks, DNS entries, and firewall allowlists don't break.

---

### `tools-install.sh` — Jenkins Bootstrap Script

Runs once on first boot via EC2 user data. All output is logged to `/var/log/user-data.log`. Every tool uses its official GPG-verified package repository — no unverified `curl | bash` patterns.

| Tool | Notes |
|---|---|
| Java 21 (OpenJDK) | Required runtime for Jenkins |
| Jenkins (latest stable) | Installed from Jenkins' own Debian repo |
| Docker CE | Installed from Docker's official repo; `jenkins` and `ubuntu` users added to the `docker` group so they can run containers without `sudo` |
| SonarQube LTS | Runs as a Docker container (`sonarqube:lts-community`) on port 9000; starts automatically with the Docker daemon |
| AWS CLI v2 | Downloaded directly from AWS (not apt) to ensure v2 — required for `eks get-token` |
| kubectl | Version resolved dynamically from `dl.k8s.io/release/stable.txt` so it tracks the latest stable release |
| eksctl | Downloaded from GitHub releases; used for EKS cluster operations not covered by `kubectl` |
| Terraform | Installed from HashiCorp's official APT repo |
| Trivy | Aqua Security's container vulnerability scanner; integrated into Jenkins pipelines for image scanning before push |
| Helm | Installed via `snap` (simplest reliable method on Ubuntu) |

---

### `ecr.tf` — Container Registries

Two ECR repositories are created, one for each application tier:

- `todo-app/backend`
- `todo-app/frontend`

Both share the same configuration:

- **`image_tag_mutability = "MUTABLE"`** — allows overwriting tags like `latest`. For production, consider `IMMUTABLE` to prevent tag overwriting and enforce traceability.
- **`scan_on_push = true`** — triggers an automatic vulnerability scan using ECR's built-in scanner every time an image is pushed. Results appear in the ECR console under the image's details.
- **`encryption_type = "AES256"`** — encrypts image layers at rest using SSE-S3.
- **`force_delete = true`** — allows `terraform destroy` to delete repositories even when they contain images. Useful during development; remove this for production to prevent accidental data loss.

**Lifecycle policies** keep storage costs in check by expiring old images. When more than 10 images exist (tagged or untagged), the oldest are automatically deleted. ECR runs these rules on its own schedule.

---

### `eks.tf` — Kubernetes Cluster

**EKS Cluster:**

The control plane is placed in private subnets. AWS fully manages the API server — you never see those nodes. `endpoint_public_access = true` is set for initial configuration so `kubectl` works from a laptop. The inline comment notes this should be flipped to `false` after kubeconfig is configured, restricting API access to within the VPC.

`authentication_mode = "API_AND_CONFIG_MAP"` supports both the legacy `aws-auth` ConfigMap and the newer EKS access entries API, giving maximum compatibility. `bootstrap_cluster_creator_admin_permissions = true` automatically grants the IAM identity that creates the cluster full admin access.

**Launch Template — max pods override:**
```bash
/etc/eks/bootstrap.sh ${cluster_name} --use-max-pods false --kubelet-extra-args '--max-pods=50'
```
By default, `t3.small` supports only 11 pods (limited by ENI/IP slot count). This bootstrap argument raises the limit to 50, which requires the VPC CNI's prefix delegation feature to be enabled so more pod IPs are available per ENI.

**Node Group:**
- 2 desired nodes across 2 AZs, scales between 1 and 3
- `ON_DEMAND` capacity — no interruption risk from Spot termination
- `max_unavailable = 1` during rolling updates — ensures at least one node is always running during upgrades

**EBS CSI Driver Addon:**
Required for any pod that uses a `PersistentVolumeClaim` backed by EBS. Deployed as a managed EKS addon, configured with the `ebs-csi-role` IRSA role so the controller pod can call EBS APIs without node-level permissions.

**`three-tier` namespace:**
Created by Terraform before ArgoCD deploys into it. This avoids a race condition where ArgoCD tries to create resources in a namespace that doesn't exist yet.

---

### `eks-auth.tf` — RBAC Mapping

```hcl
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata { name = "aws-auth"; namespace = "kube-system" }
  data = {
    mapRoles = yamlencode([
      { rolearn = eks_nodes_role_arn, username = "system:node:{{EC2PrivateDNSName}}", groups = ["system:bootstrappers", "system:nodes"] },
      { rolearn = jenkins_ec2_role_arn, username = "jenkins", groups = ["system:masters"] }
    ])
  }
  force = true
}
```

The `aws-auth` ConfigMap is the bridge between AWS IAM and Kubernetes RBAC. Without this:
- Worker nodes cannot register with the cluster (they authenticate using their IAM role)
- Jenkins cannot run `kubectl` commands against the cluster

`force = true` allows Terraform to overwrite the ConfigMap even if it was modified out-of-band (e.g. by `eksctl`).

`kubernetes_config_map_v1_data` (not `kubernetes_config_map`) is used to patch only the `data` field without destroying and recreating the entire resource, which would disrupt running nodes.

---

### `argocd.tf` — GitOps Controller

ArgoCD is installed via the official Helm chart into its own namespace, with the server exposed as a `LoadBalancer` service (creates an AWS Classic ELB):

```yaml
server:
  service:
    type: LoadBalancer
```

The chart version is pinned (`7.3.11`) for reproducibility — unpinned chart installs can break on re-apply if a new version introduces breaking changes.

**After install:**
1. Get the initial admin password: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d`
2. Get the UI address: `kubectl get svc argocd-server -n argocd`
3. Connect ArgoCD to your Git repo and define an `Application` pointing at your Kubernetes manifests

---

### `alb-controller.tf` — AWS Load Balancer Controller

The ALB Controller watches for Kubernetes `Ingress` objects and automatically creates AWS Application Load Balancers to route external traffic to pods.

**Service Account (IRSA):**

The service account is created by Terraform with the IRSA annotation that binds it to the `alb-controller-role`:
```hcl
annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn }
```
EKS injects temporary AWS credentials for that role into pods using this service account.

**Helm install key settings:**
- `serviceAccount.create = false` — uses the Terraform-created service account (which has the IAM annotation) instead of a plain one the chart would create
- `clusterName` and `vpcId` — required so the controller knows which cluster and VPC to manage load balancers in

**Using the controller** — annotate your `Ingress` resource:
```yaml
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/certificate-arn: <acm_certificate_arn output>
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
```

---

### `dns.tf` — Route 53 + ACM

**Hosted Zone:**
A public hosted zone for `johnnycloudops.xyz` is created in Route 53. After `terraform apply`, the `route53_nameservers` output gives you four NS records to add to your domain registrar under "Custom DNS". DNS propagation typically takes 10–30 minutes.

**ACM Certificate:**
Covers both the apex domain and `www.johnnycloudops.xyz`. `validation_method = "DNS"` is used (preferred over email — it's fully automatable). `create_before_destroy = true` ensures zero-downtime renewal: the new certificate is provisioned before the old one is destroyed.

**DNS Validation:**
ACM issues a CNAME challenge per domain. Terraform reads the required records from `domain_validation_options` and creates them automatically in Route 53. The `aws_acm_certificate_validation` resource then waits (up to 45 minutes) until ACM confirms ownership and issues the signed certificate.

**A Records:**
Both `johnnycloudops.xyz` and `www.johnnycloudops.xyz` point to the ALB via Route 53 alias records. Alias records are free, update automatically if the ALB endpoint changes, and work for the apex domain (which standard CNAMEs cannot serve).

> **Note:** The `data "aws_lb" "app"` block is commented out because the ALB doesn't exist until after the first Kubernetes `Ingress` resource is applied. Uncomment it once the ALB Controller has provisioned the load balancer, then re-run `terraform apply` to create the DNS records.

---

## Usage

### Prerequisites

1. The [bootstrap module](../bootstrap/README.md) has been applied — the S3 bucket and DynamoDB table must exist.
2. An EC2 key pair named `jenkins-key` exists in `us-east-2` (create via AWS console or CLI).
3. The `alb-iam-policy.json` file is present in this directory. Download it:
   ```bash
   curl -o alb-iam-policy.json \
     https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
   ```
4. AWS credentials are configured locally.
5. Terraform CLI >= 1.5.0 is installed.

### Deploy

```bash
# 1. Initialise — downloads providers and connects to the S3 backend
terraform init

# 2. Preview changes
terraform plan -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'

# 3. Apply (takes 15–20 minutes; EKS cluster alone takes ~10 min)
terraform apply -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'
```

### Post-apply steps

```bash
# Configure kubectl to talk to the new cluster
aws eks update-kubeconfig --region us-east-2 --name todo-app-cluster

# Verify nodes are Ready
kubectl get nodes

# Get ArgoCD initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

# Get ArgoCD LoadBalancer address
kubectl get svc argocd-server -n argocd

# Point your domain registrar to Route 53 nameservers
terraform output route53_nameservers
```

### Teardown

Helm releases create AWS resources (ELBs) that Terraform doesn't track. Remove them before destroying:

```bash
helm uninstall argocd -n argocd
helm uninstall aws-load-balancer-controller -n kube-system

# Wait ~2 minutes for ELBs to be deleted, then:
terraform destroy -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'
```

> If `terraform destroy` fails on the EKS cluster, check for orphaned load balancers in the AWS console (created by the ALB Controller but not removed by Helm uninstall) and delete them manually before retrying.

---

## Requirements

| Tool | Minimum Version |
|---|---|
| Terraform CLI | >= 1.5.0 |
| AWS Provider | ~> 5.0 |
| AWS CLI | v2 (required for `eks get-token`) |
| kubectl | Compatible with EKS 1.32 |

**IAM permissions required to apply this module:** EC2, EKS, ECR, IAM (roles, policies, OIDC), VPC, Route 53, ACM, S3, DynamoDB, ELB, and Kubernetes API access. Use an IAM role with `AdministratorAccess` for initial setup, then scope it down after the infrastructure is stable.
