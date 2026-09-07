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

<img width="500" height="638" alt="image" src="https://github.com/user-attachments/assets/e24b372f-384b-47c9-b67a-d812afd20ae5" />

<img width="1484" height="851" alt="Screenshot 2026-09-05 at 8 06 10 PM" src="https://github.com/user-attachments/assets/22a732be-111c-4237-9512-f6c6ef002e96" />

<img width="1497" height="833" alt="Screenshot 2026-09-05 at 7 57 05 PM" src="https://github.com/user-attachments/assets/534e25e2-2aed-4ef0-bc31-9d8cf665c0fa" />

