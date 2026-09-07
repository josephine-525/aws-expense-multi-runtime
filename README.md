# AWS Expense Demo — Multi-Runtime (Terraform + App)

Single repository for a small **expense tracker** used to compare **Lambda**, **ECS Fargate**, and **EKS** on AWS from one Terraform codebase.

The **EKS track is the deep-dive**: beyond just running the app, it covers **GitOps (ArgoCD)** — CI renders manifests and pushes to git, ArgoCD syncs, not direct `kubectl apply` — **observability** (Prometheus/Grafana + CloudWatch Container Insights, a dashboard checked in as code), and a real **EKS version upgrade** exercised live on the cluster (control plane, then node groups one AZ at a time, backed by PodDisruptionBudgets, zero pod restarts).

| Path | What |
|------|------|
| [`expenseinfra/`](expenseinfra/) | Terraform: `deployment_mode = lambda \| ecs \| eks`, modules, GitLab CI, destroy check scripts, EKS upgrade notes |
| [`expenseapp/`](expenseapp/) | Application: `frontend/`, `backend/`, Dockerfiles, GitLab CI for ECR / ECS / EKS deploy, monitoring + GitOps setup |
| [`eks-architecture.html`](eks-architecture.html) | Optional static diagram (open in a browser) |

**Layout requirement:** keep `expenseapp` and `expenseinfra` as **sibling folders** at the repo root (Terraform resolves `expenseapp` from `expenseinfra/terraform/` via `../../expenseapp` — see [`expenseinfra/terraform/paths.tf`](expenseinfra/terraform/paths.tf)).

**Read next:**
- [`expenseinfra/README.md`](expenseinfra/README.md) — Terraform, runtime comparison, EKS troubleshooting log, EKS version upgrades.
- [`expenseapp/README.md`](expenseapp/README.md) — app CI/CD, monitoring & observability, GitOps (ArgoCD), resiliency.

**CI note:** pipelines are written for GitLab; 
GitHub Actions equivalents are not included — `terraform apply` locally works fine for a portfolio demo.

<img width="628" height="750" alt="image" src="https://github.com/user-attachments/assets/c41d9e0f-786b-455e-8c30-a6a038953283" />