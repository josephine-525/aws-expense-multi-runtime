output "expenses_table_name" {
  value = aws_dynamodb_table.expenses.name
}

output "expenses_table_arn" {
  value = aws_dynamodb_table.expenses.arn
}

output "sns_budget_topic_arn" {
  value = aws_sns_topic.budget_alerts.arn
}

output "expense_image_release_ssm_parameter_name" {
  value = aws_ssm_parameter.expense_image_release_seq.name
}

output "ecr_expense_backend_repository_url" {
  value = aws_ecr_repository.expense_backend.repository_url
}

output "ecr_expense_frontend_repository_url" {
  value = aws_ecr_repository.expense_frontend.repository_url
}
