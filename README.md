# AWS Expense Demo — Multi-Runtime (Terraform + App)

Single repository for a small **expense tracker** used to compare **Lambda**, **ECS Fargate**, and **EKS** on AWS from one Terraform codebase.

| Path | What |
|------|------|
| [`expenseinfra/`](expenseinfra/) | Terraform: `deployment_mode = lambda \| ecs \| eks`, modules, GitLab CI, destroy check scripts |
| [`expenseapp/`](expenseapp/) | Application: `frontend/`, `backend/`, Dockerfiles, GitLab CI for ECR / ECS / EKS deploy |
| [`eks-architecture.html`](eks-architecture.html) | Optional static diagram (open in a browser) |

**Layout requirement:** keep `expenseapp` and `expenseinfra` as **sibling folders** at the repo root (Terraform resolves `expenseapp` from `expenseinfra/terraform/` via `../../expenseapp` — see [`expenseinfra/terraform/paths.tf`](expenseinfra/terraform/paths.tf)).

**Read next:** technical detail, CI/CD, and troubleshooting → [`expenseinfra/README.md`](expenseinfra/README.md).

**CI note:** pipelines are written for GitLab; 
GitHub Actions equivalents are not included — `terraform apply` locally works fine for a portfolio demo.

<img width="628" height="750" alt="image" src="https://github.com/user-attachments/assets/c41d9e0f-786b-455e-8c30-a6a038953283" />