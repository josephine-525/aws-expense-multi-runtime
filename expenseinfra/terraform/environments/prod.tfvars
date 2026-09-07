aws_region   = "ca-central-1"
project_name = "<your-project-name>"
# Choose runtime: lambda | ecs | eks
deployment_mode = "eks"

# Match EKS console / supported versions (see AWS EKS → Kubernetes versions).
eks_kubernetes_version = "1.35"

# t3.medium (not the t3.small default) — leaves enough headroom for the
# kube-prometheus-stack monitoring pods plus the CloudWatch Observability
# addon DaemonSets alongside the app workloads.
eks_node_instance_types = ["t3.medium"]

# Optional: custom ECR repo names (must match expenseapp GitLab
# ECR_BACKEND_REPO / ECR_FRONTEND_REPO if set).
# ecr_expense_backend_repository_name  = "expenseapp-api"
# ecr_expense_frontend_repository_name = "expenseapp-web"

# Account-wide monthly cost alert (EKS/NAT/ALB/EC2…). Replace email before apply.
# After first apply, check inbox and confirm the SNS subscription or you will not get mail.
budget_alert_email = ""
budget_monthly_usd = 20
enable_aws_budget  = true









