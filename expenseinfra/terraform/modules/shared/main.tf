data "aws_caller_identity" "current" {}

locals {
  ecr_expense_backend_repo_name  = coalesce(var.ecr_expense_backend_repository_name, "${var.project_name}-expense-backend")
  ecr_expense_frontend_repo_name = coalesce(var.ecr_expense_frontend_repository_name, "${var.project_name}-expense-frontend")
}

resource "aws_dynamodb_table" "expenses" {
  name         = "${var.project_name}-expenses"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "expense_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "expense_id"
    type = "S"
  }
}

resource "aws_ssm_parameter" "expense_image_release_seq" {
  name        = "/${var.project_name}/expense/image-release-seq"
  type        = "String"
  value       = "0"
  description = "Release counter for ECR image tags (managed by GitLab CI, not Terraform after create)."

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ecr_repository" "expense_backend" {
  name                 = local.ecr_expense_backend_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "expense_frontend" {
  name                 = local.ecr_expense_frontend_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_sns_topic" "budget_alerts" {
  name = "${var.project_name}-budget-alerts"
}

resource "aws_sns_topic_subscription" "budget_email" {
  count = var.budget_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.budget_alert_email
}

resource "aws_budgets_budget" "monthly" {
  count = var.enable_aws_budget ? 1 : 0

  account_id        = data.aws_caller_identity.current.account_id
  name              = "${var.project_name}-month-usd"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_monthly_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2024-01-01_00:00"
  time_period_end   = "2087-01-01_00:00"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}
