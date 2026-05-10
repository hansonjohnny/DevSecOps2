# Cloud Native Todo App — Full Project README

A production-grade, three-tier Todo application deployed on AWS EKS using a complete DevSecOps pipeline. The project covers everything from foundational Terraform state management through to live Kubernetes workloads served over HTTPS, with automated CI/CD, security scanning, and GitOps-driven deployments.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technology Stack](#2-technology-stack)
3. [Repository Structure](#3-repository-structure)
4. [End-to-End Architecture](#4-end-to-end-architecture)
5. [Phase 1 — Terraform State Bootstrap](#5-phase-1--terraform-state-bootstrap)
6. [Phase 2 — Core AWS Infrastructure](#6-phase-2--core-aws-infrastructure)
7. [Phase 3 — Jenkins CI/CD Setup](#7-phase-3--jenkins-cicd-setup)
8. [Phase 4 — Kubernetes Manifests & ArgoCD](#8-phase-4--kubernetes-manifests--argocd)
9. [Phase 5 — DNS & TLS (Going Live)](#9-phase-5--dns--tls-going-live)
10. [How Everything Connects](#10-how-everything-connects)
11. [Full Deployment Runbook](#11-full-deployment-runbook)
12. [Teardown](#12-teardown)
13. [Requirements & Prerequisites](#13-requirements--prerequisites)
14. [API Reference](#14-api-reference)
15. [Troubleshooting Quick Reference](#15-troubleshooting-quick-reference)

---

## 1. Project Overview

This project deploys a simple Todo application using an end-to-end cloud-native workflow:

- **Infrastructure as Code** — all AWS resources are provisioned with Terraform
- **Containerisation** — frontend (Nginx) and backend (Flask) are packaged as Docker images stored in ECR
- **Kubernetes** — workloads run on EKS with managed node groups
- **GitOps** — ArgoCD watches the Git repository and automatically syncs any manifest changes to the cluster
- **DevSecOps** — Jenkins pipelines enforce code quality (SonarQube), dependency scanning (OWASP), and container scanning (Trivy) before any image is pushed
- **TLS & DNS** — the app is served over HTTPS at `johnnycloudops.xyz` via ACM and Route 53

The application itself is intentionally simple — the real purpose of this project is to demonstrate a complete, production-style deployment pipeline from scratch.

---

## 2. Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Frontend** | HTML/CSS/JS + Nginx | Static UI served by Nginx |
| **Backend** | Python Flask + Gunicorn | REST API (todos CRUD, Redis caching) |
| **Database** | PostgreSQL 15 | Persistent todo storage |
| **Cache** | Redis 7 (Alpine) | Response caching for GET /api/todos |
| **Container Registry** | AWS ECR | Private Docker image storage |
| **Orchestration** | AWS EKS (Kubernetes 1.32) | Container runtime |
| **Infrastructure** | Terraform >= 1.5 | All AWS resources as code |
| **CI/CD** | Jenkins | Build, scan, push, and deploy pipelines |
| **GitOps** | ArgoCD | Continuous delivery from Git to cluster |
| **Code Quality** | SonarQube | Static analysis, security hotspots |
| **Dependency CVEs** | OWASP Dependency-Check | Known CVE scanning of libraries |
| **Image CVEs** | Trivy | Filesystem and image vulnerability scanning |
| **Ingress** | AWS ALB + ALB Controller | Layer 7 routing, TLS termination |
| **DNS** | Route 53 | Public hosted zone, alias records |
| **TLS** | AWS ACM | Managed certificate, DNS auto-validation |
| **State Backend** | S3 + DynamoDB | Terraform remote state and locking |

---

## 3. Repository Structure

```
DevSecOps2/
│
├── Terraform-Files/
├── bootstrap/                    # Phase 1 — run FIRST, run ONCE
│   ├── provider.tf
│   ├── variables.tf
│   ├── s3.tf
│   ├── dynamodb.tf
│   └── outputs.tf
│
├── main-infra/                   # Phase 2 — run after bootstrap
│   ├── backend.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── gather.tf
│   ├── vpc.tf
│   ├── security-groups.tf
│   ├── iam-roles.tf
│   ├── iam-policies.tf
│   ├── ec2.tf
│   ├── ecr.tf
│   ├── eks.tf
│   ├── eks-auth.tf
│   ├── argocd.tf
│   ├── alb-controller.tf
│   ├── dns.tf
│   ├── tools-install.sh
│   └── alb-iam-policy.json
│
├── Todo-app/                     # Application source code
│   ├── backend/
│   │   ├── app.py
│   │   ├── models.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   ├── frontend/
│   │   ├── index.html
│   │   ├── nginx.conf
│   │   └── Dockerfile
│   └── docker-compose.yml        # Local dev only
│
├── Jenkins-Pipeline-Code/                 # Phase 3 — CI/CD pipeline definitions
│   ├── Jenkinsfile-backend
│   └── Jenkinsfile-frontend
│
└── K8-Files/                     # Phase 4 — Kubernetes manifests
    ├── Backend/
    │   ├── deployment.yaml
    │   └── service.yaml
    ├── Config/
    │   ├── configmap.yaml
    │   └── secrets.yaml
    ├── Database/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── pvc.yaml
    ├── Frontend/
    │   ├── deployment.yaml
    │   └── service.yaml
    ├── Redis/
    │   ├── deployment.yaml
    │   └── service.yaml
    ├── ingress/
    │   └── ingress.yaml
    └── argocd/
        ├── config-app.yaml
        ├── database-app.yaml
        ├── redis-app.yaml
        ├── backend-app.yaml
        ├── frontend-app.yaml
        └── ingress-app.yaml
```

---

## 4. End-to-End Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         DEVELOPER WORKFLOW                           │
│                                                                      │
│  git push ──► Jenkins Pipeline                                       │
│                    │                                                 │
│           ┌────────┴──────────┐                                      │
│           │   Security Gates  │                                      │
│           │   SonarQube       │  ← static analysis + quality gate   │
│           │   OWASP           │  ← dependency CVE scan              │
│           │   Trivy FS        │  ← filesystem CVE scan              │
│           └────────┬──────────┘                                      │
│                    │                                                 │
│           docker build + Trivy image scan                           │
│                    │                                                 │
│           docker push ──► ECR (tagged :BUILD_NUMBER)                │
│                    │                                                 │
│           sed image tag → git commit → git push to main             │
│                    │                                                 │
│           ArgoCD detects Git change (~3 min) ──► kubectl apply      │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                        AWS INFRASTRUCTURE                            │
│                                                                      │
│  Route 53 (johnnycloudops.xyz)                                       │
│       │                                                              │
│       ▼                                                              │
│  ACM Certificate (TLS) ──► ALB (internet-facing)                    │
│                                  │                                   │
│         ┌────────────────────────┴──────────────────────┐           │
│         │           VPC  10.0.0.0/16    us-east-2        │           │
│         │                                                │           │
│         │   Public Subnets (AZ-a, AZ-b)                 │           │
│         │   ├── Jenkins EC2 + EIP  ──  CI/CD server     │           │
│         │   └── NAT Gateways       ──  outbound egress  │           │
│         │                                                │           │
│         │   Private Subnets (AZ-a, AZ-b)               │           │
│         │   └── EKS Worker Nodes                        │           │
│         │           ├── three-tier namespace            │           │
│         │           │   ├── frontend  (Nginx)           │           │
│         │           │   ├── backend   (Flask)           │           │
│         │           │   ├── postgres  (PostgreSQL+EBS)  │           │
│         │           │   └── redis     (Redis)           │           │
│         │           └── argocd namespace                │           │
│         │               └── ArgoCD (GitOps controller) │           │
│         └────────────────────────────────────────────────           │
│                                                                      │
│  ECR:      todo-app/backend    todo-app/frontend                    │
│  S3:       Terraform state file                                      │
│  DynamoDB: Terraform state lock                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow (live user request)

```
User browser
    │  HTTPS (443)
    ▼
Route 53 A record ──► ALB  (TLS terminated, cert from ACM)
                        │
            ┌───────────┴────────────┐
            │  /api/*                │  /*
            ▼                        ▼
  backend-service:5000     frontend-service:80
            │                        │
            ▼                        ▼
      Flask pod                 Nginx pod
            │
    ┌───────┴────────┐
    ▼                ▼
postgres-service  redis-service
(PostgreSQL pod)  (Redis pod)
(EBS PVC: 5Gi)
```

### CI/CD Flow (code push)

```
Developer pushes code
    │
    ▼
Jenkins (webhook / poll SCM)
    ├── SonarQube analysis ──► Quality Gate  (ABORT if fail)
    ├── OWASP scan         ──► FAIL if ≥1 Critical or ≥5 High CVEs
    ├── Trivy FS scan      ──► logs HIGH/CRITICAL findings
    ├── docker build
    ├── Trivy image scan   ──► logs HIGH/CRITICAL findings
    ├── docker push ──► ECR  (image tagged :BUILD_NUMBER)
    └── update deployment.yaml image tag ──► git push to main
                │
                ▼
    ArgoCD polls Git (every ~3 min)
                │
                ▼
    ArgoCD detects changed image tag
                │
                ▼
    Rolling update on EKS  (zero downtime)
```

---

## 5. Phase 1 — Terraform State Bootstrap

**Run once, before anything else.**

Terraform needs a place to store its own state before it can manage any AWS resources. This phase creates that foundation: an S3 bucket for state files and a DynamoDB table for state locking.

### What it creates

| Resource | Name | Purpose |
|---|---|---|
| S3 bucket | `cloud-native-buckettt` | Stores all `.tfstate` files, versioned, encrypted |
| DynamoDB table | `cloud-native-dynamodb-lock` | Prevents concurrent `terraform apply` runs |

### Why it must come first

Every other Terraform module uses `backend "s3"` — they store their state in this S3 bucket. If the bucket doesn't exist, `terraform init` on those modules fails immediately. This bootstrap module intentionally has **no remote backend** and runs with local state — solving the classic chicken-and-egg problem.

### Key design decisions

- **`prevent_destroy = true`** on both resources — a plan that would delete them fails hard. Losing the state bucket would corrupt all other Terraform state.
- **S3 versioning** — every `terraform apply` writes a new state version, enabling full rollback.
- **AES-256 encryption** — state files often contain passwords, ARNs, and private keys. Encrypted at rest at no extra cost.
- **All public access blocked** — state bucket can never be made public, even by accident.
- **DynamoDB `hash_key = "LockID"`** — Terraform's S3 backend hardcodes this exact attribute name. Case-sensitive.
- **`PAY_PER_REQUEST` billing** — lock operations are infrequent; on-demand is cheaper than provisioned capacity.

### Steps

```bash
cd bootstrap/

terraform init      # local state only — no S3 backend yet
terraform plan
terraform apply

# Save these outputs — needed in every subsequent module
terraform output
# bucket_name         = "cloud-native-buckettt"
# dynamodb_table_name = "cloud-native-dynamodb-lock"
```

---

## 6. Phase 2 — Core AWS Infrastructure

**Run after Phase 1. Takes 15–20 minutes.**

This Terraform module provisions every AWS resource the application needs: networking, compute, Kubernetes cluster, container registries, CI server, GitOps controller, load balancer controller, and DNS.

### What it creates

**Networking (`vpc.tf`)**

A VPC (`10.0.0.0/16`) spread across two Availability Zones for high availability:

| Subnet | CIDR | AZ | Purpose |
|---|---|---|---|
| Public 1 | 10.0.0.0/24 | us-east-2a | ALB, Jenkins EC2, NAT GW 1 |
| Public 2 | 10.0.1.0/24 | us-east-2b | NAT GW 2 |
| Private 1 | 10.0.10.0/24 | us-east-2a | EKS worker nodes |
| Private 2 | 10.0.11.0/24 | us-east-2b | EKS worker nodes |

One NAT Gateway per AZ — private nodes reach the internet without being publicly reachable. Two private route tables keep outbound traffic within the same AZ, avoiding cross-AZ data transfer costs.

**Security Groups (`security-groups.tf`)** — four tightly scoped groups:

| Group | Inbound | Purpose |
|---|---|---|
| `alb-sg` | TCP 80/443 from `0.0.0.0/0` | Internet traffic to ALB only |
| `eks-cluster-sg` | TCP 443 from nodes + Jenkins | Protect the Kubernetes API server |
| `eks-nodes-sg` | Node-to-node, control plane, ALB ports 80/443/5000 | Worker node traffic |
| `jenkins-sg` | TCP 22/8080/9000 from your IP only | SSH, Jenkins UI, SonarQube UI |

**IAM (`iam-roles.tf` + `iam-policies.tf`)** — five IAM roles with least-privilege policies:

| Role | Assumed by | Key permissions |
|---|---|---|
| `jenkins-ec2-role` | Jenkins EC2 (instance profile) | ECR push/pull, EKS admin, S3/DynamoDB state |
| `eks-cluster-role` | EKS control plane | EKS cluster management |
| `eks-node-role` | EKS worker nodes | Node registration, ECR pull, EBS, CNI |
| `ebs-csi-role` | EBS CSI pod (IRSA) | `ec2:CreateVolume`, `ec2:AttachVolume` |
| `alb-controller-role` | ALB Controller pod (IRSA) | Create/manage ALBs, target groups |

IRSA (IAM Roles for Service Accounts) uses an OIDC provider tied to the EKS cluster so individual pods can assume IAM roles without any node-level AWS credentials.

**Jenkins EC2 (`ec2.tf`)** — `m7i-flex.large` in a public subnet:
- 30 GB gp3 encrypted root volume
- Static Elastic IP (survives instance stops/starts)
- `user_data` runs `tools-install.sh` on first boot, which installs: Java 21, Jenkins, Docker, SonarQube (Docker container on port 9000), AWS CLI v2, kubectl, eksctl, Terraform, Trivy, Helm

**ECR (`ecr.tf`)** — two private repositories:
- `todo-app/backend` — scan on push, lifecycle policy retains last 10 images
- `todo-app/frontend` — same configuration

**EKS (`eks.tf`)** — managed Kubernetes cluster:
- Version 1.32, control plane in private subnets
- Node group: `t3.small`, 2 desired / 1 min / 3 max, ON_DEMAND
- Launch template overrides max pods to 50 (default for t3.small is 11)
- EBS CSI Driver addon for PVC provisioning
- `three-tier` namespace pre-created to avoid ArgoCD race conditions
- `aws-auth` ConfigMap maps EKS node role and Jenkins IAM role to Kubernetes RBAC

**ArgoCD (`argocd.tf`)** — installed via Helm (chart 7.3.11), exposed as a LoadBalancer Service.

**ALB Controller (`alb-controller.tf`)** — installed via Helm (chart 1.8.1), watches for Ingress resources and provisions AWS ALBs automatically.

**DNS + TLS (`dns.tf`)**:
- Route 53 public hosted zone for `johnnycloudops.xyz`
- ACM certificate for apex + `www` subdomain, DNS-validated automatically by Terraform
- Route 53 A records pointing to the ALB (added after the ALB exists in Phase 5)

### Prerequisites before applying

```bash
# 1. Create the EC2 key pair for Jenkins SSH access
aws ec2 create-key-pair --key-name jenkins-key --region us-east-2 \
  --query 'KeyMaterial' --output text > jenkins-key.pem
chmod 400 jenkins-key.pem

# 2. Download the ALB Controller IAM policy
curl -o main-infra/alb-iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
```

### Apply

```bash
cd main-infra/

terraform init   # connects to the S3 backend provisioned in Phase 1

terraform plan -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'

terraform apply -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'
```

### Post-apply checklist

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-2 --name todo-app-cluster

# Verify nodes are Ready (may take 2–3 min)
kubectl get nodes

# Print all outputs for reference
terraform output

# Get ArgoCD initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

# Get ArgoCD UI address
kubectl get svc argocd-server -n argocd

# Copy Route 53 nameservers — add to your domain registrar under "Custom DNS"
terraform output route53_nameservers
```

---

## 7. Phase 3 — Jenkins CI/CD Setup

**Run after Phase 2. Jenkins is already installed — this phase configures it.**

### Access Jenkins and SonarQube

```
Jenkins URL:   http://<jenkins_public_ip>:8080
SonarQube URL: http://<jenkins_public_ip>:9000

# Get Jenkins public IP
terraform output jenkins_public_ip -state=main-infra/terraform.tfstate

# Get initial Jenkins admin password
ssh -i jenkins-key.pem ubuntu@<jenkins_public_ip>
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

# SonarQube default credentials: admin / admin  (change on first login)
```

### Jenkins plugins to install

After unlocking Jenkins, install the **suggested plugins** plus these additional ones:

- SonarQube Scanner
- OWASP Dependency-Check
- Pipeline (if not in suggested)
- Git (if not in suggested)

### Jenkins credentials to configure

Navigate to **Manage Jenkins → Credentials → System → Global credentials → Add Credential**:

| Credential ID | Kind | Value | Used in |
|---|---|---|---|
| `ACCOUNT_ID` | Secret text | Your 12-digit AWS account ID | ECR URI construction |
| `ECR_REPO1` | Secret text | `todo-app/frontend` | Frontend pipeline |
| `ECR_REPO2` | Secret text | `todo-app/backend` | Backend pipeline |
| `nvdApiKey` | Secret text | NVD API key | OWASP rate limit bypass |
| `github-token` | Secret text | GitHub PAT (repo scope) | Pushing deployment.yaml to Git |

### Jenkins tools to configure

Navigate to **Manage Jenkins → Global Tool Configuration**:

| Tool | Name | Configuration |
|---|---|---|
| JDK | `jdk` | Point to `/usr/lib/jvm/java-21-openjdk-amd64` |
| SonarQube Scanner | `sonar-scanner` | Auto-install latest |
| Dependency-Check | `DP-Check` | Auto-install latest |

### SonarQube server configuration

Navigate to **Manage Jenkins → Configure System → SonarQube servers**:
1. Name: `sonar-server`
2. URL: `http://localhost:9000`
3. Authentication token: generate in SonarQube → My Account → Security

### SonarQube project setup

In SonarQube (`http://<jenkins_ip>:9000`):
1. Create project with key `cloud-native-backend` and name `cloud-native-backend`
2. Create project with key `cloud-native-frontend` and name `cloud-native-frontend`
3. Generate access tokens for each project

### Create Jenkins pipeline jobs

Create two **Pipeline** jobs:

**`todo-backend-pipeline`:**
- Definition: Pipeline script from SCM
- SCM: Git → `https://github.com/hansonjohnny/DevSecOps2.git`
- Branch: `*/main`
- Script Path: `Jenkinsfiles/Jenkinsfile-backend`

**`todo-frontend-pipeline`:**
- Same settings, Script Path: `Jenkinsfiles/Jenkinsfile-frontend`

Configure a **GitHub webhook** or **SCM polling** to trigger builds on push to `main`.

### What each pipeline does

Both pipelines follow the same DevSecOps pattern (11 stages):

```
Stage 1   Cleanup Workspace        cleanWs() — no stale files from previous builds
Stage 2   Checkout                 git clone from configured SCM
Stage 3   SonarQube Analysis       scan source for bugs, smells, security hotspots
Stage 4   Quality Gate             wait for SonarQube result — ABORT pipeline if failed
Stage 5   OWASP Dependency-Check   scan dependencies for known CVEs
              └── FAIL if ≥1 Critical or ≥5 High severity CVEs found
Stage 6   Trivy FS Scan            scan source filesystem before building image
Stage 7   Docker Build             docker build from Dockerfile in Todo-app/
Stage 8   Trivy Image Scan         scan built image for OS and app-level CVEs
Stage 9   ECR Push                 authenticate → tag :BUILD_NUMBER → push to ECR
Stage 10  Re-checkout              ensure K8-Files/ is available in workspace
Stage 11  Update deployment.yaml   sed image tag → git commit → git push to main

Post      cleanWs()                always clean workspace on success or failure
```

Three independent security checkpoints before any image reaches ECR:
1. SonarQube Quality Gate — catches code quality and security hotspot regressions
2. OWASP Dependency-Check — catches known CVEs in third-party libraries
3. Trivy — catches OS-level and application-level vulnerabilities in the container image

**Stage 11 is the GitOps trigger.** It writes the new ECR image tag back to `K8-Files/Backend/deployment.yaml` (or Frontend) and pushes to `main`. ArgoCD detects this change within ~3 minutes and initiates a Kubernetes rolling update automatically.

### Pipeline options explained

| Option | Value | Reason |
|---|---|---|
| Timeout | 120 minutes | OWASP downloads the NVD database on first run (~40 min) |
| Concurrent builds | Disabled | Prevents race conditions on docker tag and git push |
| Build history kept | Last 10 | Manages disk usage on the Jenkins agent |

---

## 8. Phase 4 — Kubernetes Manifests & ArgoCD

**Manifests live in Git. ArgoCD deploys them. No manual `kubectl apply` needed after initial setup.**

### Workloads deployed into the cluster

| Component | Image | Port | Strategy |
|---|---|---|---|
| Frontend | ECR `todo-app/frontend:<tag>` (Nginx) | 80 | RollingUpdate (maxUnavailable: 0) |
| Backend | ECR `todo-app/backend:<tag>` (Flask) | 5000 | RollingUpdate (maxUnavailable: 0) |
| PostgreSQL | `postgres:15` | 5432 | Recreate (stateful) |
| Redis | `redis:7-alpine` | 6379 | Recreate (stateful) |

All workloads run in the `three-tier` namespace. All services are `ClusterIP` — only reachable inside the cluster. External traffic enters exclusively through the Ingress / ALB.

### Configuration and secrets

**ConfigMap (`app-config`)** — non-sensitive values:
```
POSTGRES_HOST  = postgres-service
POSTGRES_PORT  = 5432
REDIS_HOST     = redis-service
REDIS_PORT     = 6379
DATABASE_URL   = postgresql://postgres:postgres@postgres-service:5432/tododb
FLASK_ENV      = production
```

**Secrets** — base64-encoded credentials:
- `postgres-secret` → `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- `redis-secret` → `REDIS_PASSWORD`

Service hostnames (`postgres-service`, `redis-service`) resolve via Kubernetes DNS within the same namespace. They are always stable — unlike pod IPs which change on every restart.

### Deployment order — ArgoCD sync waves

ArgoCD waits for each wave to be healthy before starting the next, preventing race conditions:

```
Wave 1 ──► todo-config     ConfigMap + Secrets
               ↓ healthy
Wave 2 ──► todo-database   PostgreSQL Deployment + Service + PVC (EBS 5Gi)
           todo-redis      Redis Deployment + Service
               ↓ healthy
Wave 3 ──► todo-backend    Flask Deployment + Service
           todo-frontend   Nginx Deployment + Service
               ↓ healthy
Wave 4 ──► todo-ingress    ALB Ingress  ← triggers ALB creation in AWS
```

### Key manifest decisions explained

**PostgreSQL uses `Recreate` strategy** — two PostgreSQL instances writing to the same EBS volume simultaneously would corrupt data. `Recreate` terminates the old pod before starting the new one. Brief downtime during updates is acceptable for a single-replica database.

**Backend and Frontend use `RollingUpdate` with `maxUnavailable: 0`** — zero-downtime deploys. A new pod must pass its readiness probe on `/health` before the old pod is terminated.

**`PersistentVolumeClaim` (`postgres-pvc`, 5 Gi, `gp2-csi`)** — the EBS CSI Driver (installed in Phase 2) provisions a real AWS EBS volume when this PVC is created. Data survives pod restarts and deletions. The `subPath: pgdata` mount matches the directory structure the PostgreSQL image expects during first initialisation.

**Redis password via command override:**
```yaml
command: ["redis-server", "--requirepass", "$(REDIS_PASSWORD)"]
```
The official Redis image starts with no authentication. The password is injected from the Secret as an environment variable and substituted into the startup command.

**Health probes** — every deployment has both a readiness and liveness probe:
- Readiness probe: removes the pod from the Service endpoint list while it is starting or unhealthy — no traffic is sent to an unready pod
- Liveness probe: restarts the pod if it becomes permanently stuck or deadlocked
- PostgreSQL and Redis use `exec` probes (`pg_isready`, `redis-cli ping`); HTTP workloads use `httpGet` on their health endpoints

**Ingress annotations** drive the ALB Controller to provision an internet-facing ALB with TLS:
- `alb.ingress.kubernetes.io/scheme: internet-facing` — public ALB
- `alb.ingress.kubernetes.io/target-type: ip` — routes directly to pod IPs (bypasses kube-proxy)
- `alb.ingress.kubernetes.io/certificate-arn` — ACM cert from Phase 2
- `alb.ingress.kubernetes.io/ssl-redirect: "443"` — HTTP → HTTPS redirect
- `/api/*` → `backend-service:5000`, `/*` → `frontend-service:80`

### ArgoCD sync policy (all apps)

```yaml
syncPolicy:
  automated:
    prune: true       # delete Kubernetes resources removed from Git
    selfHeal: true    # revert any manual kubectl changes automatically
  syncOptions:
    - CreateNamespace=true
```

`selfHeal: true` means Git is the only source of truth. Any manual `kubectl` changes are reverted within minutes. `prune: true` means removing a manifest from Git removes the resource from the cluster — be careful with the PVC.

### Apply ArgoCD Application resources

```bash
# One command — ArgoCD enforces wave ordering regardless of apply order
kubectl apply -f K8-Files/argocd/

# Watch waves sync in order
kubectl get applications -n argocd -w

# Watch pods come up in three-tier namespace
kubectl get pods -n three-tier -w
```

### Verify

```bash
# All pods should reach Running / Ready
kubectl get pods -n three-tier

# Services should have ClusterIPs
kubectl get svc -n three-tier

# Ingress should show an ALB hostname under ADDRESS (~2 min after wave 4)
kubectl get ingress -n three-tier

# Get the ALB hostname
kubectl get ingress todo-app-ingress -n three-tier \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## 9. Phase 5 — DNS & TLS (Going Live)

**Run after Phase 4, once the ALB has been provisioned.**

### Point your domain to Route 53

During Phase 2, a Route 53 hosted zone was created. Get the nameservers:

```bash
terraform output route53_nameservers -state=main-infra/terraform.tfstate
```

Add all four nameservers to your domain registrar (Namecheap, GoDaddy, etc.) as **Custom DNS / Custom nameservers**. DNS propagation takes 10–30 minutes.

### Wire Route 53 A records to the ALB

The `data "aws_lb" "app"` block in `dns.tf` was commented out during Phase 2 because the ALB didn't exist yet. Now it does.

1. Open `main-infra/dns.tf` and uncomment the `data "aws_lb" "app"` data source block.
2. Re-apply:

```bash
cd main-infra/
terraform apply -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'
```

This creates Route 53 A alias records for both `johnnycloudops.xyz` and `www.johnnycloudops.xyz` pointing to the ALB. Alias records are free, update automatically if the ALB endpoint changes, and support the apex domain (which CNAMEs cannot).

### Verify TLS and the live app

```bash
# After DNS propagates (10–30 min):
curl -I https://johnnycloudops.xyz
# Expected: HTTP/2 200, valid ACM certificate in response headers

curl https://johnnycloudops.xyz/api/todos
# Expected: JSON array (empty on first run)

# HTTP should redirect to HTTPS
curl -I http://johnnycloudops.xyz
# Expected: 301 redirect to https://
```

The application is now live at `https://johnnycloudops.xyz`.

---

## 10. How Everything Connects

This section traces the integration points between all components:

**Jenkins → ECR:**
Jenkins EC2 uses its IAM instance profile (`jenkins-ec2-role`) which holds `AmazonEC2ContainerRegistryFullAccess`. It authenticates with `aws ecr get-login-password` and pushes images tagged `:BUILD_NUMBER` — each build produces a uniquely tagged, immutable image enabling full rollback.

**Jenkins → Git (GitOps trigger):**
After the ECR push, Stage 11 of each pipeline uses the `github-token` credential to `git push` the updated `deployment.yaml` (with the new image tag) back to `main`. This single file change is what ArgoCD detects and acts on.

**ArgoCD → Git:**
ArgoCD polls `github.com/hansonjohnny/DevSecOps2` on `main` every ~3 minutes. When it detects a diff between Git and the live cluster state (e.g. a changed image tag), it triggers a sync.

**ArgoCD → Kubernetes:**
ArgoCD runs inside the cluster (`argocd` namespace) and uses the in-cluster service account with cluster-admin permissions. It applies manifests using standard Kubernetes API calls.

**EKS nodes → ECR (image pull):**
Worker nodes assume `eks-node-role`, which has `AmazonEC2ContainerRegistryReadOnly`. When a pod is scheduled with an ECR image URL, the kubelet pulls it using these credentials automatically — no `imagePullSecret` needed.

**Backend → PostgreSQL:**
`DATABASE_URL=postgresql://postgres:postgres@postgres-service:5432/tododb` — Kubernetes DNS resolves `postgres-service` to the ClusterIP of the PostgreSQL Service. The Service load-balances to the PostgreSQL pod.

**Backend → Redis:**
`REDIS_HOST=redis-service`, `REDIS_PASSWORD` from Secret — same DNS pattern. The backend caches `GET /api/todos` responses in Redis to reduce PostgreSQL load.

**ALB Controller → AWS:**
The ALB Controller pod assumes `alb-controller-role` via IRSA (OIDC token exchange). When it detects the Ingress resource in wave 4, it calls AWS APIs to create the ALB, configure listeners (HTTP:80, HTTPS:443), create target groups pointing to pod IPs, and attach the ACM certificate.

**EBS CSI Driver → AWS:**
The CSI driver pod assumes `ebs-csi-role` via IRSA. When `postgres-pvc` is created in wave 2, the driver calls `ec2:CreateVolume` to provision a 5 GiB gp2 EBS volume in the same AZ as the PostgreSQL pod, then calls `ec2:AttachVolume` to mount it.

**Route 53 → ALB → Users:**
Route 53 A alias records resolve `johnnycloudops.xyz` to the ALB DNS name. The ALB terminates TLS using the ACM certificate, then routes decrypted HTTP/2 traffic to `backend-service` or `frontend-service` based on the request path.

---

## 11. Full Deployment Runbook

Complete sequential steps, zero to live:

```bash
# ── PHASE 1: Bootstrap state infrastructure ──────────────────────────
cd bootstrap/
terraform init
terraform apply
cd ..

# ── PHASE 2: Prerequisites ───────────────────────────────────────────
# Create EC2 key pair
aws ec2 create-key-pair --key-name jenkins-key --region us-east-2 \
  --query 'KeyMaterial' --output text > jenkins-key.pem
chmod 400 jenkins-key.pem

# Download ALB IAM policy
curl -o main-infra/alb-iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# ── PHASE 2: Deploy AWS infrastructure (~15-20 min) ───────────────────
cd main-infra/
terraform init
terraform apply -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'

# Save outputs
terraform output > ../infra-outputs.txt

# Configure kubectl
aws eks update-kubeconfig --region us-east-2 --name todo-app-cluster
kubectl get nodes   # wait until all nodes show Ready

# Copy Route 53 nameservers to domain registrar now
# (propagation takes 10-30 min — do this early)
terraform output route53_nameservers
cd ..

# ── PHASE 3: Configure Jenkins ────────────────────────────────────────
# Open http://<jenkins_public_ip>:8080
# 1. Unlock with: ssh in → sudo cat /var/lib/jenkins/secrets/initialAdminPassword
# 2. Install suggested plugins + SonarQube Scanner + OWASP Dependency-Check
# 3. Add credentials: ACCOUNT_ID, ECR_REPO1, ECR_REPO2, nvdApiKey, github-token
# 4. Configure SonarQube server (Manage Jenkins → Configure System)
# 5. Configure JDK, SonarQube Scanner, OWASP tools (Global Tool Configuration)
# 6. Create two Pipeline jobs pointing to Jenkinsfiles/

# Configure SonarQube: http://<jenkins_public_ip>:9000
# 1. Login admin/admin → change password
# 2. Create projects: cloud-native-backend, cloud-native-frontend
# 3. Generate tokens → add to Jenkins SonarQube config

# ── PHASE 3: Run initial pipeline builds ─────────────────────────────
# Trigger todo-backend-pipeline in Jenkins
#   → scans → builds → pushes to ECR → updates K8-Files/Backend/deployment.yaml
# Trigger todo-frontend-pipeline in Jenkins
#   → scans → builds → pushes to ECR → updates K8-Files/Frontend/deployment.yaml

# ── PHASE 4: Deploy Kubernetes workloads via ArgoCD ──────────────────
kubectl apply -f K8-Files/argocd/

# Watch sync waves execute (wave 1→2→3→4)
kubectl get applications -n argocd -w

# Watch pods come up
kubectl get pods -n three-tier -w
# Wait until all pods show: Running + Ready

# Get the ALB hostname (appears ~2 min after wave 4)
kubectl get ingress todo-app-ingress -n three-tier \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# ── PHASE 5: Wire DNS to ALB ─────────────────────────────────────────
# 1. Uncomment data "aws_lb" "app" block in main-infra/dns.tf
cd main-infra/
terraform apply -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'
cd ..

# ── VERIFY ───────────────────────────────────────────────────────────
# Wait for DNS to propagate (if not already done)
curl -I https://johnnycloudops.xyz        # should return HTTP/2 200
curl https://johnnycloudops.xyz/api/todos # should return []
```

---

## 12. Teardown

Order matters — reverse of deployment to avoid dependency failures:

```bash
# ── Step 1: Remove Helm releases (they created AWS ELBs Terraform doesn't know about)
helm uninstall argocd -n argocd
helm uninstall aws-load-balancer-controller -n kube-system

# Wait ~2 minutes for ELBs to be fully deleted in AWS
sleep 120

# ── Step 2: Destroy main infrastructure (~10–15 min)
cd main-infra/
terraform destroy -var='jenkins_ssh_cidr=YOUR.IP.HERE/32'
cd ..

# ── Step 3: Destroy bootstrap LAST
# WARNING: This deletes all Terraform state history for every module.
# First, temporarily remove prevent_destroy from bootstrap/s3.tf and bootstrap/dynamodb.tf
cd bootstrap/
terraform destroy
```

> If `terraform destroy` fails on the EKS cluster or VPC, check the AWS console for orphaned resources created by the ALB Controller (load balancers, security group rules, ENIs). Delete them manually and retry.

---

## 13. Requirements & Prerequisites

### Local tools

| Tool | Minimum Version | Purpose |
|---|---|---|
| Terraform CLI | >= 1.5.0 | Infrastructure provisioning |
| AWS CLI | v2 | Authentication, `eks get-token`, ECR login |
| kubectl | Compatible with EKS 1.32 | Cluster management |
| Helm | >= 3.0 | Manual Helm operations during teardown |
| Git | Any | Repository operations |

### AWS account requirements

- IAM user or role with `AdministratorAccess` (or scoped equivalent) for Terraform
- At least 2 Elastic IP addresses available in `us-east-2` (for NAT Gateways)
- EKS cluster limit not reached in the account

### External services required

| Service | Why needed | Where to get it |
|---|---|---|
| GitHub repository | Source code + Kubernetes manifest hosting | github.com |
| GitHub Personal Access Token | Jenkins pushes `deployment.yaml` updates to Git | GitHub → Settings → Developer settings → PAT |
| NVD API key | OWASP Dependency-Check avoids NVD API rate limiting | https://nvd.nist.gov/developers/request-an-api-key |
| Domain name | For `johnnycloudops.xyz` or your equivalent | Any registrar (Namecheap, GoDaddy, etc.) |

### Network access required

| Port | Protocol | Source | Service |
|---|---|---|---|
| 22 | TCP | Your IP | SSH to Jenkins EC2 |
| 80 | TCP | Internet | HTTP (redirects to HTTPS) |
| 443 | TCP | Internet | HTTPS app traffic |
| 8080 | TCP | Your IP | Jenkins web UI |
| 9000 | TCP | Your IP | SonarQube web UI |

---

## 14. API Reference

The Flask backend exposes the following endpoints, all reachable externally via `/api/*` on the ALB:

| Method | Path | Description | Caching |
|---|---|---|---|
| GET | `/health` | Health check — used by Kubernetes readiness/liveness probes | None |
| GET | `/api/todos` | List all todos | Redis-cached |
| POST | `/api/todos` | Create a new todo | Cache invalidated |
| PATCH | `/api/todos/:id` | Toggle todo completion status | Cache invalidated |
| DELETE | `/api/todos/:id` | Delete a todo | Cache invalidated |

### Run locally

```bash
cd Todo-app/
docker-compose up --build

# Frontend: http://localhost:3000
# Backend:  http://localhost:5000
# API:      http://localhost:5000/api/todos
```

The `docker-compose.yml` wires up all four services (frontend, backend, PostgreSQL, Redis) locally with the same environment variable names used in the Kubernetes ConfigMap and Secrets.

---

## 15. Troubleshooting Quick Reference

| Symptom | First step | Common cause |
|---|---|---|
| Pod stuck in `Pending` | `kubectl describe pod <name> -n three-tier` | Insufficient CPU/memory on nodes, PVC not bound |
| Pod in `CrashLoopBackOff` | `kubectl logs <name> -n three-tier --previous` | Missing env var, failed DB connection, app crash on startup |
| PVC stuck in `Pending` | `kubectl get pods -n kube-system \| grep ebs-csi` | EBS CSI driver not running, wrong StorageClass name, IAM permissions |
| Ingress has no ALB address | `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller` | Missing subnet tags, IAM permissions, ALB Controller not running |
| ArgoCD `OutOfSync` and won't auto-heal | `argocd app diff <name>` then `argocd app sync <name> --force` | Immutable field changed, CRD missing, RBAC issue |
| Jenkins pipeline fails at ECR push | Check `aws sts get-caller-identity` on the Jenkins EC2 | `jenkins-ec2-role` missing ECR permissions |
| Jenkins can't run `kubectl` | Check `aws-auth` ConfigMap | Jenkins IAM role not mapped to `system:masters` |
| App returns 502 Bad Gateway | `kubectl logs <backend-pod> -n three-tier` | Backend pod not ready, `/health` endpoint not responding |
| DNS not resolving | `nslookup johnnycloudops.xyz` | Nameservers not updated at registrar, propagation delay |
| ACM certificate stuck `Pending validation` | Check Route 53 for CNAME records | Terraform created them automatically — check hosted zone |
| Redis auth failure | Check `REDIS_PASSWORD` in pod env | Secret value has trailing newline — re-encode with `echo -n` |
| PostgreSQL `data directory has wrong ownership` | Delete pod, let it restart | Remove `subPath: pgdata` issue — ensure it is set in volumeMount |
| `terraform apply` fails on EKS | Check for orphaned load balancers in EC2 console | ALB Controller created ELBs that block VPC deletion |
