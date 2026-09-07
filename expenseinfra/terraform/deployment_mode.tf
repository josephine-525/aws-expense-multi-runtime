locals {
  enable_expense_lambda = var.deployment_mode == "lambda"
  enable_expense_ecs    = var.deployment_mode == "ecs"
  enable_expense_eks    = var.deployment_mode == "eks"
}
