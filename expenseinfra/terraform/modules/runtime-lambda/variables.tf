variable "enabled" {
  type = bool
}

variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "expense_frontend_index_tpl" {
  type = string
}

variable "expense_lambda_handler_py" {
  type = string
}

variable "dynamodb_expenses_table_name" {
  type = string
}

variable "dynamodb_expenses_table_arn" {
  type = string
}
