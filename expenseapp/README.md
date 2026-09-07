# expenseapp

Application code for the expense demo:

| Directory | Contents |
|-----------|----------|
| `frontend/` | `index.html.tpl` — legacy: Terraform `templatefile` + API URL; ECS: baked into Docker (often empty `API_BASE` for same-origin ALB). |
| `backend/` | `lambda/handler.py` (Lambda zip) and `server.py` + `Dockerfile` (ECS / local HTTP). |

Infrastructure (Terraform) lives in the **expenseinfra** repository. Clone both repos as **siblings** (`expenseapp` next to `expenseinfra`) or set `TF_VAR_expenseapp_repo_path` when applying.

### Local Docker

From this repo root:

```bash
docker compose up --build
```

- UI: [http://localhost:3000](http://localhost:3000) (static `index.html` built with `API_BASE=http://localhost:8080`)
- API: [http://localhost:8080](http://localhost:8080) (`/expenses`, `/months`, `/summary`)
- DynamoDB Local: port `8000`; the backend creates `expenses-local` on first start when `DYNAMODB_ENDPOINT` is set.

For production-like API URLs in the browser (e.g. behind another host), rebuild the frontend image with `docker compose build --build-arg API_BASE=https://your-api.example frontend` (see `docker-compose.yml` `frontend.build.args`).

### GitLab CI → ECR → ECS (when infra uses `enable_expense_ecs`)

Pipeline: `.gitlab-ci.yml` — **`resolve-version`** bumps SSM and sets `IMAGE_VERSION`; **build** pushes each image as `:latest`, `:$CI_COMMIT_SHA`, and `:$IMAGE_VERSION`; **deploy** runs `aws ecs update-service --force-new-deployment`. **Default branch only** (no MR Docker jobs in this file).

Set **GitLab CI/CD variables** (same AWS account/region as Terraform): `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, and **`PROJECT_NAME`** (must match Terraform `project_name` — used for **ECS cluster / service names** and the **SSM parameter path**). Optional **`ECR_BACKEND_REPO`** / **`ECR_FRONTEND_REPO`** if Terraform overrides ECR repo names.

**Image tags (automatic):** on each **default-branch** pipeline, job `resolve-version` reads SSM `/${PROJECT_NAME}/expense/image-release-seq`, increments it, writes it back, and sets `IMAGE_VERSION` to `v001`, `v002`, … (three digits). Build jobs push `:latest`, `:$CI_COMMIT_SHA`, and `:$IMAGE_VERSION` to both ECR repos. **You do not edit any version file.** If you **terraform destroy** the infra and apply again, the parameter is recreated at `0`, so the next run goes **v001** again (expected).

The IAM user/role needs **ECR push**, **ecs:UpdateService** / **ecs:DescribeServices**, and **ssm:GetParameter** + **ssm:PutParameter** on `arn:aws:ssm:${region}:${account}:parameter/${PROJECT_NAME}/expense/image-release-seq` (see Terraform output `expense_image_release_ssm_parameter_name`).

After deploy, open the app at Terraform output **`expense_app_url`** (ALB HTTP URL), **not** `http://localhost:3000` (that URL is only for local Docker Compose).

### AWS runtime: Lambda zip vs ECR + ECS

- **Smallest change from today**: keep **API Gateway + Lambda** and optionally switch the function to a **container image** (same code, still Lambda, still scales to zero).
- **ECR + ECS on Fargate** is already “serverless” in the sense of **no EC2 to manage**; you add a **task definition**, **service**, and usually an **ALB** (or public IP). More moving parts than Lambda, better when you need long-lived connections, larger images, or stricter parity with this Docker setup.
- **“ECS Serverless”** in AWS marketing often points at **Fargate** (above) or **App Runner** (simpler, fewer knobs). Pick **Fargate** when you want full VPC/ECS control; **App Runner** when one HTTP service per container is enough.

Practical sequence: validate with **Docker Compose** locally, then either **Lambda container image** or **Fargate + ALB** depending on whether you want to stay on API Gateway or standardize on long-running containers.

---

## GitLab CI → EKS (when infra uses `enable_expense_eks`)

`deploy-eks` in `.gitlab-ci.yml` builds images (same `resolve-version`/`IMAGE_VERSION` flow as ECS), then:

1. Installs/updates the **AWS Load Balancer Controller** (Helm), reading `vpcId` from `aws eks describe-cluster` and the IRSA role ARN from SSM (see expenseinfra README's Observability section).
2. Installs/updates **kube-prometheus-stack** and **ArgoCD** (Helm) — see the two sections below.
3. Renders `k8s/eks-serviceaccount.yaml` / `k8s/eks-workload.yaml` (`envsubst`) into `k8s/rendered/`, commits, and pushes — **ArgoCD applies them**, not this job directly.
4. Waits for the ArgoCD `Application` to reach `Synced` + `Healthy`, then checks pod rollout status and waits for the ALB hostname.

Required GitLab CI/CD variables beyond the ECS ones: `GRAFANA_ADMIN_PASSWORD` (masked) and `GITOPS_PUSH_TOKEN` (masked — see GitOps section). `EKS_EXPENSE_BACKEND_ROLE_ARN`, `EKS_AWS_LBC_ROLE_ARN`, `EKS_ALB_SG_ID` are **not** CI variables — they're read from SSM at deploy time (published by expenseinfra).

---

## Resiliency (EKS)

`k8s/eks-workload.yaml`: both Deployments run **3 replicas** (bumped from 2) with a **`PodDisruptionBudget`** (`minAvailable: 2`) each. This isn't just a static config choice — it was exercised for real during an EKS control-plane + node-group upgrade (1.34 → 1.35, see expenseinfra README's "EKS version upgrades" section): a node holding 2 of a Deployment's 3 replicas got drained, and the PDB forced the eviction API to replace those pods **one at a time** instead of both at once, keeping at least 2/3 capacity online throughout. Zero pod-level downtime, verified by restart counts staying at 0.

Combined with the existing `podAntiAffinity` + `topologySpreadConstraints` (spread across both nodes/AZs — see expenseinfra README), this is the actual safety net behind any voluntary disruption: node group upgrades, `kubectl drain`, cluster scaling — not just a config that looks correct on paper.

With only 2 replicas, `minAvailable: 1` would have been the right call instead (still "never zero," just a smaller floor) — see the reasoning in expenseinfra's upgrade section for why replica count and PDB ratio should scale together, and why real prod services rarely run only 2 replicas of anything customer-facing.

---

## Monitoring & Observability (EKS)

**Metrics — kube-prometheus-stack** (Prometheus + Grafana + node-exporter + kube-state-metrics + Alertmanager), namespace `monitoring`, installed by `deploy-eks`. Storage is **ephemeral (emptyDir)** — no EBS CSI driver in this cluster, and metrics history isn't worth persisting for a learning cluster; history is lost on pod restart.

No public Ingress for Grafana/Prometheus (same "port-forward only" policy as everything else internal in this project):

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80      # http://localhost:3001, user: admin
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

**Custom dashboard, checked in as code**: `k8s/expense-grafana-dashboard.yaml` is a `ConfigMap` labeled `grafana_dashboard: "1"` — the same mechanism kube-prometheus-stack's own bundled dashboards use. The Grafana sidecar watches for this label and loads/updates the dashboard automatically; no manual "import dashboard" step. Panels: CPU, memory, container restarts, network I/O, pod count, and nginx request rate — all scoped to `namespace="expense"`.

**Frontend request metrics**: nginx doesn't expose Prometheus metrics natively. `k8s/eks-workload.yaml`'s frontend Deployment runs an **`nginx-prometheus-exporter` sidecar** that scrapes nginx's `stub_status` (enabled in `frontend/nginx-eks.conf`, restricted to `127.0.0.1`) and re-exposes it as `/metrics` on `:9113`. A `ServiceMonitor` tells Prometheus to scrape it.

> **Gotcha worth remembering:** `ServiceMonitor.spec.selector` matches labels on the **Service object itself** (`metadata.labels`), not `spec.selector` (which is how the Service finds Pods) — two unrelated fields that happen to share the name "selector". Also, kube-prometheus-stack's Prometheus only watches `ServiceMonitor`/`PodMonitor` objects carrying the label `release: kube-prometheus-stack` (its `serviceMonitorSelector`) — miss either one and Prometheus silently drops the target (shows up under `droppedTargets`, not an error).

**Logs + Container Insights (CloudWatch)** — installed by **expenseinfra**, not this repo:

```
/aws/containerinsights/{cluster}/application   # pod stdout/stderr
/aws/containerinsights/{cluster}/host          # node-level logs
/aws/containerinsights/{cluster}/dataplane     # kubelet / container runtime
```

CloudWatch console → **Container Insights → Performance monitoring** for CPU/mem dashboards without needing Grafana.

---

## GitOps (ArgoCD)

`deploy-eks` installs **ArgoCD** (Helm, namespace `argocd`, `dex`/`notifications`/`applicationSet` disabled — not needed for a single app, trims pod count on the t3.medium nodes). An `Application` (`k8s/argocd-application.yaml`) watches this repo's **`k8s/rendered/`** directory with `syncPolicy.automated: { prune: true, selfHeal: true }`.

**Deploys no longer happen via direct `kubectl apply`.** The flow is:

```
CI builds image → renders k8s/*.yaml (envsubst) into k8s/rendered/ → git commit + push → ArgoCD detects the diff → syncs
```

⚠️ **`selfHeal: true` means manual `kubectl apply`/`kubectl edit` against these resources gets silently reverted** back to whatever's committed in `k8s/rendered/`. To change something, edit the source template (`k8s/eks-workload.yaml`, etc.) and let CI re-render + push — don't hand-edit the live objects.

**`GITOPS_PUSH_TOKEN`** (masked CI variable) is a GitLab **personal access token**, scoped to this project, used for two things:
1. **ArgoCD's read credential** for cloning this (private) repo — configured as a `Secret` labeled `argocd.argoproj.io/secret-type: repository`.
2. **CI's write credential** for pushing the rendered manifests.

A real prod setup would split this into two least-privilege tokens (read-only for ArgoCD, write for CI); one shared token is a scoped-down trade-off acceptable for a learning project.

> **Gotcha worth remembering:** GitLab **fine-grained personal access tokens** split read and write into separate permissions under "Code" — granting only the write/commit permission is **not** enough for ArgoCD to clone the repo. It needs **`Code: Download`** explicitly, in addition to whatever lets CI push. The error surfaces as `Access denied: ... requires ... [Code: Download]` in the `Application`'s `status.conditions`, with `sync.status` stuck at `Unknown`.

**Access ArgoCD's UI** (port-forward only, no Ingress):

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d   # admin password
```

**Troubleshooting**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `git push` rejected: "Updates were rejected because a pushed branch tip is behind" | CI's checkout was behind `origin/main` (e.g. a previous retried job already pushed a commit) — a non-fast-forward rejection, **not** an auth error | `git fetch origin "$CI_DEFAULT_BRANCH" && git checkout -B "$CI_DEFAULT_BRANCH" "origin/$CI_DEFAULT_BRANCH"` before rendering/committing, every run |
| ArgoCD `Application` stuck `sync.status: Unknown`, health `Healthy` | Repo credential token missing `Code: Download` scope (see above) | Regenerate the fine-grained token with `Code: Download` **and** the write scope; update `GITOPS_PUSH_TOKEN` |
| Nginx request-rate panel empty; Prometheus `Status → Targets` shows nothing for `expense-frontend` | `Service.metadata.labels` missing — `ServiceMonitor` selector never matched (see ServiceMonitor gotcha above) | Add `metadata.labels: {app: expense-frontend}` to the Service (not just `spec.selector`) |

