# CI/CD Pipeline — Backend (DevSecOps)

A fully automated **DevSecOps pipeline** for the backend of the `Todo-app`. It integrates static code analysis, dependency vulnerability scanning, container image scanning, Docker builds, AWS ECR publishing, and Kubernetes deployment updates — all orchestrated through Jenkins.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Environment & Credentials](#environment--credentials)
4. [Pipeline Options](#pipeline-options)
5. [Pipeline Stages](#pipeline-stages)
   - [1. Cleanup Workspace](#1-cleanup-workspace)
   - [2. Checkout](#2-checkout)
   - [3. SonarQube Analysis](#3-sonarqube-analysis)
   - [4. Quality Gate](#4-quality-gate)
   - [5. OWASP Dependency-Check Scan](#5-owasp-dependency-check-scan)
   - [6. Trivy File System Scan](#6-trivy-file-system-scan)
   - [7. Docker Image Build](#7-docker-image-build)
   - [8. Trivy Image Scan](#8-trivy-image-scan)
   - [9. ECR Image Pushing](#9-ecr-image-pushing)
   - [10. Checkout Code (Re-checkout)](#10-checkout-code-re-checkout)
   - [11. Update Kubernetes Deployment](#11-update-kubernetes-deployment)
6. [Post Actions](#post-actions)
7. [Reports & Artifacts](#reports--artifacts)
8. [Failure Conditions](#failure-conditions)
9. [Directory Structure](#directory-structure)

---

## Overview

```
Git Push → Jenkins Trigger
    │
    ├── Code Quality   →  SonarQube Analysis + Quality Gate
    ├── Dependency CVEs →  OWASP Dependency-Check
    ├── Filesystem CVEs →  Trivy FS Scan
    ├── Build          →  Docker Build
    ├── Image CVEs     →  Trivy Image Scan
    ├── Publish        →  Push to AWS ECR
    └── Deploy         →  Update Kubernetes deployment.yaml via Git
```

The pipeline enforces security at **three separate checkpoints** before any image reaches a container registry, making it suitable for production-grade DevSecOps workflows.

---

## Prerequisites

The following tools and plugins must be available on the Jenkins server:

| Requirement | Purpose |
|---|---|
| **Jenkins** with Pipeline plugin | Pipeline execution |
| **JDK** (configured as `jdk` tool) | Java runtime for SonarScanner |
| **SonarQube Scanner** (configured as `sonar-scanner`) | Static code analysis |
| **SonarQube Server** (configured as `sonar-server`) | Quality gate evaluation |
| **OWASP Dependency-Check** plugin (configured as `DP-Check`) | Dependency CVE scanning |
| **Trivy** (installed on Jenkins agent) | Container & filesystem CVE scanning |
| **Docker** (installed on Jenkins agent) | Building and tagging images |
| **Git** (installed on Jenkins agent) | Committing deployment updates |

---

## Environment & Credentials

All sensitive values are injected from **Jenkins Credentials**.

| Variable | Credential ID | Description |
|---|---|---|
| `AWS_ACCOUNT_ID` | `ACCOUNT_ID` | AWS account number used to construct the ECR URI |
| `AWS_ECR_REPO_NAME` | `ECR_REPO2` | Name of the ECR repository for the backend image |
| `AWS_DEFAULT_REGION` | *(hardcoded)* | `us-east-2` — AWS region for ECR |
| `REPOSITORY_URI` | *(derived)* | Full ECR base URI: `<account>.dkr.ecr.us-east-2.amazonaws.com/` |
| `NVD_KEY` | `nvdApiKey` | NVD API key to avoid OWASP rate limiting |
| `GITHUB_TOKEN` | `github-token` | Personal access token for pushing to GitHub |

> **Security note:** All credentials are managed through Jenkins' built-in credential store and are never exposed in logs or the repository.

---

## Pipeline Options

```groovy
timeout(time: 120, unit: "MINUTES")
disableConcurrentBuilds()
buildDiscarder(logRotator(numToKeepStr: "10"))
```

| Option | Value | Reason |
|---|---|---|
| **Timeout** | 120 minutes | Accommodates the first OWASP NVD database download, which can be slow |
| **Concurrent builds** | Disabled | Prevents race conditions on Docker builds and Git pushes |
| **Build history** | Last 10 builds | Keeps disk usage manageable |

---

## Pipeline Stages

### 1. Cleanup Workspace

```groovy
cleanWs()
```

Wipes the Jenkins workspace at the start of every build, ensuring no stale files from a previous run can interfere with the current one.

---

### 2. Checkout

```groovy
checkout scm
```

Checks out the source code from the configured SCM (Git). The branch being built is logged via `${env.BRANCH_NAME}`.

---

### 3. SonarQube Analysis

**Directory:** `Todo-app/backend or frontend`

Runs the SonarQube Scanner against the backend or frontend source code and reports results to the configured SonarQube server.

```
Project Key:  cloud-native-backend & cloud-native-frontend
Project Name: cloud-native-backend & cloud-native-frontend
```

This stage identifies code smells, bugs, security hotspots, and code coverage gaps without stopping the build on its own — the next stage handles that.

---

### 4. Quality Gate

```groovy
waitForQualityGate abortPipeline: true
```

Polls the SonarQube server (up to **10 minutes**) for the Quality Gate result. If the gate **fails** (e.g., too many bugs or security issues), the pipeline is **aborted immediately** — the build will not proceed to any further stage.

---

### 5. OWASP Dependency-Check Scan

**Directory:** `Todo-app/backend or frontend`

Scans all project dependencies for known CVEs using the **OWASP Dependency-Check** tool.

Key behaviours:

- Uses a **persistent NVD data cache** at `/var/lib/jenkins/.dependency-check-data` to avoid re-downloading the full vulnerability database on every run.
- Generates both **XML** and **HTML** reports under `reports/owasp/`.
- Enables **experimental analyzers** for broader coverage.
- Authenticates to the NVD API using `$NVD_KEY` to avoid rate limiting.

**Failure thresholds (via `dependencyCheckPublisher`):**

| Severity | Threshold |
|---|---|
| Critical | **≥ 1** will fail the build |
| High | **≥ 5** will fail the build |

---

### 6. Trivy File System Scan

**Directory:** `Todo-app/backend or forntend`

Scans the **source code and filesystem** for vulnerabilities before building a Docker image — a "shift left" security practice.

Two scans are run:

| Scan | Severity | Exit Code | Purpose |
|---|---|---|---|
| Informational | `LOW, MEDIUM` | `0` (never fails) | Visibility only — logged to console |
| Enforcement | `HIGH, CRITICAL` | `0` *(currently)* | Output saved to `reports/trivy/fs-scan.json` |

> **Note:** The enforcement scan's `--exit-code` is currently set to `0`, meaning it will not fail the build. Change to `--exit-code 1` to enforce a hard stop on HIGH/CRITICAL filesystem findings in production.

---

### 7. Docker Image Build

**Directory:** `Todo-app/backend or frontend`

Builds the backend Docker image using the `Dockerfile` in the backend directory.

```bash
docker system prune -f      # Remove unused data
docker container prune -f   # Remove stopped containers
docker build -t ${AWS_ECR_REPO_NAME} .
```

The image is tagged with the ECR repository name at this stage. Build number tagging happens at the ECR push stage.

---

### 8. Trivy Image Scan

Scans the **built Docker image** for OS-level and application-level CVEs.

Two scans are run (same pattern as the FS scan):

| Scan | Severity | Exit Code | Output |
|---|---|---|---|
| Informational | `LOW, MEDIUM` | `0` | Console table |
| Enforcement | `HIGH, CRITICAL` | `0` *(currently)* | `reports/trivy/image-scan.json` |

> **Note:** Same caveat as above — set `--exit-code 1` to enforce hard failures on critical image vulnerabilities in production.

---

### 9. ECR Image Pushing

Authenticates to AWS ECR and pushes the image with a build-number tag:

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-2 \
  | docker login --username AWS --password-stdin <REPOSITORY_URI>

# Tag with build number
docker tag ${AWS_ECR_REPO_NAME} ${REPOSITORY_URI}${AWS_ECR_REPO_NAME}:${BUILD_NUMBER}

# Push
docker push ${REPOSITORY_URI}${AWS_ECR_REPO_NAME}:${BUILD_NUMBER}
```

Each build produces a **uniquely tagged, immutable image** in ECR, enabling full rollback capability.

---

### 10. Checkout Code (Re-checkout)

A second `checkout scm` is performed here to ensure the Kubernetes manifest files (`K8-Files/`) are available in the workspace after the Docker build steps (which may have modified the working directory state).

---

### 11. Update Kubernetes Deployment

**Directory:** `K8-Files/Backend or frontend`

Automatically updates the Kubernetes `deployment.yaml` with the new image tag and commits it back to the `main` branch of the GitHub repository.

```bash
# Update image line in deployment.yaml
sed -i "s|image:.*|image: <REPOSITORY_URI><REPO_NAME>:<BUILD_NUMBER>|g" deployment.yaml

# Commit and push
git add deployment.yaml
git commit -m "ci: update backend image to build <BUILD_NUMBER>"
git push https://<GIT_USER_NAME>:<GITHUB_TOKEN>@github.com/<GIT_USER_NAME>/DevSecOps2.git HEAD:main
```

This follows a **GitOps pattern** — the desired cluster state is always reflected in Git, and a tool like ArgoCD or Flux can automatically sync the updated manifest to the cluster.

| Config | Value |
|---|---|
| Repository | `DevSecOps2` |
| GitHub user | `hansonjohnny` |
| Git email | `hansonjohnny648@gmail.com` |
| Target branch | `main` |

---

## Post Actions

```groovy
post {
    always {
        cleanWs()
    }
}
```

The workspace is **always cleaned up** after every build — success or failure — to prevent disk accumulation on the Jenkins agent.

---

## Reports & Artifacts

| Report | Location | Format | Stage |
|---|---|---|---|
| OWASP Dependency-Check | `reports/owasp/dependency-check-report.xml` | XML + HTML | Stage 5 |
| Trivy FS Scan | `reports/trivy/fs-scan.json` | JSON | Stage 6 |
| Trivy Image Scan | `reports/trivy/image-scan.json` | JSON | Stage 8 |

OWASP reports are automatically published to the Jenkins build UI via `dependencyCheckPublisher`. Trivy JSON reports are saved to disk and can be parsed by downstream tools or uploaded to a dashboard.

---

## Failure Conditions

The pipeline will **abort or fail** under the following conditions:

| Condition | Stage | Behaviour |
|---|---|---|
| SonarQube Quality Gate fails | Quality Gate | Pipeline aborted |
| ≥ 1 Critical CVE in dependencies | OWASP Scan | Build failed |
| ≥ 5 High CVEs in dependencies | OWASP Scan | Build failed |
| Pipeline timeout exceeded | Any | Build aborted after 120 min |

> Trivy HIGH/CRITICAL findings currently do **not** fail the build (`--exit-code 0`). Update to `--exit-code 1` in stages 6 and 8 to enforce this.

---

## Directory Structure

```
.
├── Todo-app/
│   └── backend/          # Application source code & Dockerfile
├── K8-Files/
│   └── Backend/
│       └── deployment.yaml   # Kubernetes deployment manifest (auto-updated)
└── reports/              # Generated during pipeline run (not committed)
    ├── owasp/
    │   ├── dependency-check-report.xml
    │   └── dependency-check-report.html
    └── trivy/
        ├── fs-scan.json
        └── image-scan.json
```
