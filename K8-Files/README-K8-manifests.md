# Kubernetes Manifests & ArgoCD Applications

This directory contains all Kubernetes manifests for the three-tier Todo application and the ArgoCD `Application` resources that tell ArgoCD where to find and how to deploy them. ArgoCD watches the Git repository and automatically applies any changes — no manual `kubectl apply` needed after initial setup.

---

## Application Architecture

```
                        Internet
                           │
                           ▼
                    ┌─────────────┐
                    │   Ingress   │  ALB (AWS Load Balancer Controller)
                    │  port 80/443│  TLS terminated at ALB
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
    ┌──────────────────┐     ┌──────────────────┐
    │  frontend-service│     │  backend-service  │
    │  (ClusterIP :80) │     │  (ClusterIP :5000)│
    └────────┬─────────┘     └────────┬──────────┘
             │                        │
             ▼                        ▼
    ┌──────────────────┐     ┌──────────────────┐
    │  Frontend Pod    │     │  Backend Pod      │
    │  (Nginx)         │     │  (Flask+Gunicorn) │
    └──────────────────┘     └────────┬──────────┘
                                      │
                        ┌─────────────┴─────────────┐
                        │                           │
                        ▼                           ▼
             ┌──────────────────┐       ┌──────────────────┐
             │  postgres-service│       │  redis-service   │
             │  (ClusterIP:5432)│       │  (ClusterIP:6379)│
             └────────┬─────────┘       └────────┬─────────┘
                      │                          │
                      ▼                          ▼
             ┌──────────────────┐       ┌──────────────────┐
             │  PostgreSQL Pod  │       │  Redis Pod       │
             │  (postgres:15)   │       │ (redis:7-alpine) │
             └────────┬─────────┘       └──────────────────┘
                      │
                      ▼
             ┌──────────────────┐
             │   postgres-pvc   │  EBS volume (5Gi, gp2-csi)
             └──────────────────┘
```

---

## Repository Structure

```
K8-Files/
├── Backend/
│   ├── deployment.yaml       # Flask + Gunicorn Deployment
│   └── service.yaml          # ClusterIP Service on port 5000
│
├── Config/
│   ├── configmap.yaml        # Non-sensitive env vars
│   └── secrets.yaml          # Base64-encoded credentials
│
├── Database/
│   ├── deployment.yaml       # PostgreSQL Deployment
│   ├── service.yaml          # ClusterIP Service on port 5432
│   └── pvc.yaml              # 5Gi EBS PersistentVolumeClaim
│
├── Frontend/
│   ├── deployment.yaml       # Nginx Deployment
│   └── service.yaml          # ClusterIP Service on port 80
│
├── Redis/
│   ├── deployment.yaml       # Redis Deployment
│   └── service.yaml          # ClusterIP Service on port 6379
│
├── ingress/
│   └── ingress.yaml          # ALB Ingress — routes traffic to services
│
└── argocd/
    ├── config-app.yaml       # ArgoCD App for Config   (wave 1)
    ├── database-app.yaml     # ArgoCD App for Database (wave 2)
    ├── redis-app.yaml        # ArgoCD App for Redis    (wave 2)
    ├── backend-app.yaml      # ArgoCD App for Backend  (wave 3)
    ├── frontend-app.yaml     # ArgoCD App for Frontend (wave 3)
    └── ingress-app.yaml      # ArgoCD App for Ingress  (wave 4)
```

---

## Deployment Order — Sync Waves

ArgoCD sync waves control the order in which resources are applied within a sync operation. Lower wave numbers are applied first, and ArgoCD waits for each wave's resources to become healthy before starting the next. This prevents race conditions — the backend must not start before the ConfigMap and Secrets it depends on exist.

```
Wave 1 ──► Config (ConfigMap + Secrets)
               │  must be healthy
               ▼
Wave 2 ──► Database (PostgreSQL + PVC) + Redis   [parallel]
               │  must be healthy
               ▼
Wave 3 ──► Backend (Flask) + Frontend (Nginx)    [parallel]
               │  must be healthy
               ▼
Wave 4 ──► Ingress (ALB)
```

| Wave | ArgoCD App | Resources Created |
|------|------------|-------------------|
| 1 | `todo-config` | ConfigMap, 2 Secrets |
| 2 | `todo-database` | PostgreSQL Deployment, Service, PVC |
| 2 | `todo-redis` | Redis Deployment, Service |
| 3 | `todo-backend` | Backend Deployment, Service |
| 3 | `todo-frontend` | Frontend Deployment, Service |
| 4 | `todo-ingress` | Ingress (triggers ALB creation) |

---

## Config Files

### `Config/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: three-tier
data:
  POSTGRES_HOST: "postgres-service"
  POSTGRES_PORT: "5432"
  REDIS_HOST:    "redis-service"
  REDIS_PORT:    "6379"
  DATABASE_URL:  "postgresql://postgres:postgres@postgres-service:5432/tododb"
  FLASK_ENV:     "production"
```

A ConfigMap stores non-sensitive configuration as plain key-value pairs. Pods reference individual keys — if the ConfigMap changes, pods must be restarted to pick up the new values.

**Why service hostnames instead of IP addresses?** Kubernetes DNS resolves `postgres-service` to the ClusterIP of the Service object. This is stable across pod restarts, whereas pod IPs change every time a pod is recreated. Within the same namespace, the short name (`postgres-service`) resolves; the full form is `postgres-service.three-tier.svc.cluster.local`.

**Separation of concerns:** Only non-sensitive values live here. Credentials belong in Secrets. Note that `DATABASE_URL` embeds the password inline — this is acceptable for development but should use a Secret reference or External Secrets in production.

---

### `Config/secrets.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: three-tier
type: Opaque
data:
  POSTGRES_USER:     cG9zdGdyZXM=   # postgres
  POSTGRES_PASSWORD: cG9zdGdyZXM=   # postgres
  POSTGRES_DB:       dG9kb2Ri       # tododb
---
apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
  namespace: three-tier
type: Opaque
data:
  REDIS_PASSWORD: c2VjcmV0         # secret
```

The `data` field requires **base64-encoded** values. Base64 is encoding, not encryption — Secrets are stored in etcd, and on EKS, etcd encryption at rest is enabled by default.

**How to encode/decode:**
```bash
echo -n "myvalue" | base64    # encode  (-n omits the trailing newline)
echo "bXl2YWx1ZQ==" | base64 -d  # decode
```

The `-n` flag on `echo` is critical — a trailing newline changes the base64 output and causes authentication failures at runtime.

**Two secrets, two consumers:**
- `postgres-secret` — consumed by the PostgreSQL pod to initialise the database user, password, and database name on first start. Also available for other services that need to connect directly with the postgres superuser.
- `redis-secret` — consumed by both the Redis pod (to set the `--requirepass` argument at startup) and the backend pod (to authenticate when connecting to Redis).

> **Production recommendation:** Do not commit real Secret values to Git. Use [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), [External Secrets Operator](https://external-secrets.io/), or AWS Secrets Manager with the External Secrets Operator to manage credentials outside the repository.

---

## Backend

### `Backend/deployment.yaml`

**Rolling update strategy:**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

- `maxSurge: 1` — during a deploy, one extra pod is created (briefly 2 pods running simultaneously)
- `maxUnavailable: 0` — no existing pod is terminated until the new one is Ready
- Combined effect: zero-downtime deployments. The old pod keeps serving traffic until the new pod passes its readiness probe

**Container image:**
```yaml
image: 493042495566.dkr.ecr.us-east-2.amazonaws.com/todo-app/backend:1
```
Pulled from ECR. The tag (`:1`) is what the Jenkins pipeline updates in Git after a successful build and push. ArgoCD detects the manifest change and triggers a rolling update.

**Environment variables — two sources:**

From ConfigMap (`configMapKeyRef`):
```yaml
- name: REDIS_HOST
  valueFrom:
    configMapKeyRef:
      name: app-config
      key: REDIS_HOST
```

From Secret (`secretKeyRef`):
```yaml
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: redis-secret
      key: REDIS_PASSWORD
```

Referencing individual keys (rather than `envFrom` which injects all keys at once) is more explicit and avoids accidentally exposing keys the container doesn't need.

**Resource requests and limits:**

| | CPU | Memory |
|---|---|---|
| Request | 250m (0.25 cores) | 256Mi |
| Limit | 500m (0.5 cores) | 512Mi |

- **Requests** — the amount the scheduler reserves on a node when placing the pod. A 2-vCPU node can fit at most 8 pods each requesting 250m.
- **Limits** — the hard ceiling. CPU over-limit causes throttling; memory over-limit causes OOMKill and pod restart.
- Always setting both prevents a runaway pod from consuming all node resources and evicting other workloads.

**Probes:**
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 5000
  initialDelaySeconds: 10   # wait 10s after container start before first check
  periodSeconds: 5          # check every 5 seconds

livenessProbe:
  httpGet:
    path: /health
    port: 5000
  initialDelaySeconds: 20   # longer delay — don't kill pod during startup
  periodSeconds: 10
```

- **Readiness probe** — while failing, the pod is removed from the Service's endpoint list and receives no traffic. Used to hold traffic until Flask has fully initialised (database pool connected, etc.).
- **Liveness probe** — if it fails, Kubernetes kills and restarts the pod. Used to recover from deadlocks or hung processes the app cannot self-recover from.
- The longer `initialDelaySeconds` on the liveness probe (20 vs 10) gives the app time to start before Kubernetes considers killing it — if the liveness delay were too short, Kubernetes would restart the pod before it ever became ready.
- Both probes call `/health` — the Flask app must expose this endpoint and return HTTP 2xx when healthy.

**ArgoCD sync wave annotation:**
```yaml
annotations:
  argocd.argoproj.io/sync-wave: "1"
```
This annotation on the Deployment (inside the manifest, not the ArgoCD Application) fine-tunes ordering within a wave. Here it ensures the Deployment is applied after any namespace-level resources in the same sync.

---

### `Backend/service.yaml`

```yaml
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
    - port: 5000
      targetPort: 5000
```

`ClusterIP` creates a stable virtual IP reachable only within the cluster. The `selector` matches pod labels from the Deployment — the Service automatically discovers and load-balances across all Ready backend pods. The Ingress controller routes `/api` traffic to this Service by name (`backend-service:5000`).

---

## Database

### `Database/deployment.yaml`

**`Recreate` strategy:**
```yaml
strategy:
  type: Recreate
```
PostgreSQL is stateful. Running two instances simultaneously against the same data volume causes corruption — both processes would write to the same files. `Recreate` terminates the existing pod before starting the new one, ensuring only one instance ever accesses the volume at a time. The trade-off is a brief downtime window during updates.

**Volume mount with subPath:**
```yaml
volumeMounts:
  - name: postgres-storage
    mountPath: /var/lib/postgresql/data
    subPath: pgdata
```
`subPath: pgdata` is required because PostgreSQL initialises its data directory by creating a `pgdata` subdirectory. Mounting the raw PVC root directly at `/var/lib/postgresql/data` triggers a "data directory has wrong ownership" error on first start. The subPath scopes the mount to that subdirectory, matching what the PostgreSQL image expects.

**Readiness and liveness probes:**
```yaml
readinessProbe:
  exec:
    command: ["pg_isready", "-U", "postgres"]
```
`pg_isready` is PostgreSQL's built-in connectivity checker. It exits 0 when the server accepts connections. An HTTP probe would not work here — PostgreSQL uses its own binary wire protocol, not HTTP.

---

### `Database/service.yaml`

ClusterIP on port 5432. The backend connects via `postgres-service:5432`. Kubernetes DNS resolves this hostname to the Service's virtual IP, which load-balances to the (single) PostgreSQL pod. The database is never exposed outside the cluster.

---

### `pvc.yaml`

```yaml
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp2-csi
  resources:
    requests:
      storage: 5Gi
```

A PersistentVolumeClaim (PVC) is a request for storage. When this resource is created, the EBS CSI driver (installed as an EKS addon via Terraform) automatically provisions a 5 GiB AWS EBS volume and binds it to the claim.

- **`ReadWriteOnce`** — the volume can be mounted read-write by a single node at a time. This is the only access mode EBS supports and is correct for a single-replica database.
- **`storageClassName: gp2-csi`** — selects the EBS CSI StorageClass. This must match a StorageClass that exists in the cluster; the EKS addon creates this class automatically.
- **`storage: 5Gi`** — EBS volumes can be expanded later without recreating the PVC (but cannot be shrunk).

**Data persistence:** The PVC and the EBS volume behind it survive pod restarts and pod deletions. Database data is only lost if the PVC itself is deleted. Because ArgoCD has `prune: true`, be careful not to remove the PVC manifest from Git while the database has live data — ArgoCD will delete the PVC (and the volume) if the file disappears from the repository.

---

## Frontend

### `Frontend/deployment.yaml`

The frontend is a stateless Nginx container serving a pre-built static application (React or similar). Because it holds no state, rolling updates are safe — multiple instances can run simultaneously during a deploy without coordination issues.

**Resources:**

| | CPU | Memory |
|---|---|---|
| Request | 100m | 128Mi |
| Limit | 250m | 256Mi |

Lighter than the backend — Nginx serving static files uses minimal CPU. Lower requests allow more frontend pods to fit on the same nodes, which matters when scaling out.

**Probes** check `GET /` on port 80. Nginx returns 200 for the index page immediately on startup, so initial delays are short (5s readiness, 10s liveness).

---

### `Frontend/service.yaml`

ClusterIP on port 80. The Ingress routes all non-API traffic here, forwarding to whichever frontend pods are Ready.

---

## Redis

### `Redis/deployment.yaml`

**Password via command override:**
```yaml
command:
  - redis-server
  - --requirepass
  - $(REDIS_PASSWORD)
```
The official Redis image starts with no authentication by default. Passing `--requirepass` at startup enables password protection. `$(REDIS_PASSWORD)` is shell variable substitution — Kubernetes resolves the env var from the Secret before executing the command.

**`redis:7-alpine`** — the Alpine Linux variant is ~30 MB vs ~110 MB for the full Debian image. Smaller image means faster pulls and a reduced attack surface.

**`Recreate` strategy** — same reasoning as PostgreSQL. Redis should not have two instances running simultaneously against the same state.

**Probes:**
```yaml
readinessProbe:
  exec:
    command: ["redis-cli", "ping"]
```
`redis-cli ping` returns `PONG` when the server is responsive. Note: this probe does not authenticate, which is acceptable for readiness (the server responds to `ping` even before connections from the app). For production with strict auth requirements, use `redis-cli -a $(REDIS_PASSWORD) ping`.

---

### `Redis/service.yaml`

ClusterIP on port 6379. The backend connects via `redis-service:6379` as configured in the ConfigMap.

---

## Ingress

### `ingress/ingress.yaml`

The Ingress is the single entry point for external traffic. The AWS Load Balancer Controller reads this resource and provisions an Application Load Balancer in AWS.

**Key annotations:**

| Annotation | Value | Effect |
|---|---|---|
| `kubernetes.io/ingress.class` | `alb` | Tells the ALB Controller to handle this Ingress |
| `alb.ingress.kubernetes.io/scheme` | `internet-facing` | Creates a public ALB (not internal) |
| `alb.ingress.kubernetes.io/target-type` | `ip` | Routes directly to pod IPs, bypassing kube-proxy |
| `alb.ingress.kubernetes.io/certificate-arn` | ACM ARN | Attaches your TLS certificate to the HTTPS listener |
| `alb.ingress.kubernetes.io/listen-ports` | `[{"HTTP":80},{"HTTPS":443}]` | Opens both listeners on the ALB |
| `alb.ingress.kubernetes.io/ssl-redirect` | `"443"` | Redirects all HTTP requests to HTTPS automatically |

**`target-type: ip`** is preferred over `instance` on EKS because pods can move between nodes. Routing by pod IP is always accurate, whereas instance-mode routing adds a second hop through kube-proxy.

**Path routing:**
- `/api` → `backend-service:5000` — all API calls from the frontend are prefixed with `/api`
- `/` → `frontend-service:80` — all other traffic goes to Nginx

`pathType: Prefix` means any URL starting with `/api` (e.g. `/api/todos`, `/api/tasks/1`) matches the backend rule. Kubernetes evaluates more specific paths first, so `/api` takes priority over `/` for API requests.

The certificate ARN in the annotation is the output from `terraform output acm_certificate_arn` — update this value with your actual ARN before applying.

---

## ArgoCD Applications

Each component has its own ArgoCD `Application` resource, giving independent sync status, health indicators, and rollback capability per component. A broken Database manifest does not block the Config sync from succeeding.

All applications share the same configuration pattern:

```yaml
spec:
  project: default
  source:
    repoURL: https://github.com/hansonjohnny/DevSecOps2.git
    targetRevision: main
    path: K8-Files/<Component>
  destination:
    server: https://kubernetes.default.svc
    namespace: three-tier
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Sync Policy — what each setting does

**`automated`** — ArgoCD polls the Git repo (default: every 3 minutes) and automatically applies detected changes. No manual `argocd app sync` required.

**`prune: true`** — if a manifest is removed from Git, ArgoCD deletes the corresponding resource from the cluster. Without this, removed manifests leave orphaned resources that consume node resources indefinitely.

**`selfHeal: true`** — if someone manually modifies a cluster resource with `kubectl` (e.g. scales a deployment to 3 replicas), ArgoCD detects the drift from Git and reverts it within minutes. Git is the single source of truth; manual changes are not permitted to persist.

**`CreateNamespace: true`** — ArgoCD creates the `three-tier` namespace if it doesn't exist. The namespace is also created by Terraform, but this option makes the ArgoCD Applications independently deployable.

---

### `argocd/config-app.yaml` — Wave 1

Applied first. Creates the `app-config` ConfigMap and both Secrets. Every other component depends on these — pods that reference a ConfigMap or Secret that doesn't exist will fail with `CreateContainerConfigError` and never start.

---

### `argocd/database-app.yaml` — Wave 2

```yaml
syncOptions:
  - SkipDryRunOnMissingResource=true
  - RespectIgnoreDifferences=true
```

**`SkipDryRunOnMissingResource`** — PVCs with dynamic provisioning cannot be validated with a dry run before they exist. This tells ArgoCD to skip dry-run validation for resources that don't yet exist and apply them directly.

**`RespectIgnoreDifferences`** — Kubernetes and storage controllers mutate certain fields after creation (e.g. StorageClass defaults written to a PVC spec). These mutations would otherwise show as permanent drift. This option tells ArgoCD to honour any `ignoreDifferences` configuration and not flag them as out-of-sync.

---

### `argocd/redis-app.yaml` — Wave 2

Applied at wave 2 alongside the database. Redis has no dependency on PostgreSQL so both can initialise in parallel. The backend (wave 3) will not start until both are healthy.

---

### `argocd/backend-app.yaml` — Wave 3

Applied after Config, Database, and Redis are healthy. Flask starts, connects to PostgreSQL and Redis using the injected environment variables. The readiness probe on `/health` prevents traffic from reaching the backend pod until those connections are established.

---

### `argocd/frontend-app.yaml` — Wave 3

Applied alongside the backend. Nginx has no runtime dependencies and becomes ready almost immediately. It can start in parallel with the backend without issues.

---

### `argocd/ingress-app.yaml` — Wave 4

Applied last. By wave 4, all Services and their pods exist and are healthy. The ALB Controller reads the Ingress resource and provisions the Application Load Balancer, registering both `backend-service` and `frontend-service` as target groups. The ALB only starts forwarding traffic once the target group health checks pass.

Applying the Ingress last prevents the ALB from routing traffic to services that don't exist yet, which would cause 503 errors during the initial deployment.

---

## Initial Deployment

```bash
# Apply all ArgoCD Application resources
# (wave ordering is enforced by ArgoCD, not by kubectl apply order)
kubectl apply -f argocd/

# Watch sync progress across all apps
kubectl get applications -n argocd -w

# Or use the ArgoCD CLI
argocd app list
```

### Verify deployment

```bash
# All pods should be Running
kubectl get pods -n three-tier

# Services should show ClusterIPs
kubectl get svc -n three-tier

# Ingress should show an ALB hostname under ADDRESS (takes ~2 min)
kubectl get ingress -n three-tier

# Get the ALB address
kubectl get ingress todo-app-ingress -n three-tier \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## Updating the Application

To deploy a new image version:

1. Jenkins pipeline builds and pushes the new image to ECR (e.g. tag `:2`)
2. The pipeline updates `image:` in the relevant `deployment.yaml` in Git
3. ArgoCD detects the change within ~3 minutes and triggers a rolling update
4. The new pod passes its readiness probe; only then does Kubernetes terminate the old pod
5. Zero downtime — traffic is only sent to the new pod once it is healthy

To trigger an immediate sync:
```bash
argocd app sync todo-backend
```

---

## Troubleshooting

**Pod stuck in `Pending`:**
```bash
kubectl describe pod <pod-name> -n three-tier
# Look for: insufficient CPU/memory, PVC not bound, node selector mismatch
```

**Pod in `CrashLoopBackOff`:**
```bash
kubectl logs <pod-name> -n three-tier --previous
# Check: missing env vars, failed DB connection, app startup errors
```

**PVC stuck in `Pending`:**
```bash
kubectl describe pvc postgres-pvc -n three-tier
# Check: EBS CSI driver pods are Running, StorageClass exists
kubectl get pods -n kube-system | grep ebs-csi
kubectl get storageclass
```

**ArgoCD shows `OutOfSync` and won't auto-heal:**
```bash
argocd app diff todo-database   # see what's different
argocd app sync todo-database --force
```

**Backend cannot connect to PostgreSQL:**
```bash
# Verify DNS resolution from inside the cluster
kubectl run debug --rm -it --image=busybox -n three-tier -- sh
nslookup postgres-service
# Verify the service has endpoints (pod is ready)
kubectl get endpoints postgres-service -n three-tier
```

**Ingress not getting an ALB address:**
```bash
# Check ALB Controller logs for errors
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
# Verify public subnets have the required tag
# kubernetes.io/role/elb = 1  must exist on public subnets
```
