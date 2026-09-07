variable "project_name" {
  type = string
}

variable "budget_alert_email" {
  type = string
}

variable "budget_monthly_usd" {
  type = number
}

variable "enable_aws_budget" {
  type = bool
}

variable "ecr_expense_backend_repository_name" {
  type     = string
  default  = null
  nullable = true
}

variable "ecr_expense_frontend_repository_name" {
  type     = string
  default  = null
  nullable = true
}
