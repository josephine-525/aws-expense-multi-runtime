variable "enabled" {
  type = bool
}

variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "dynamodb_expenses_table_arn" {
  type = string
}

variable "ecr_expense_backend_repository_url" {
  type = string
}

variable "ecr_expense_frontend_repository_url" {
  type = string
}
