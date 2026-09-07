output "expense_alb_dns_name" {
  value = var.enabled ? aws_lb.expense[0].dns_name : null
}

output "expense_app_url" {
  value = var.enabled ? "http://${aws_lb.expense[0].dns_name}" : null
}

output "ecs_cluster_name" {
  value = var.enabled ? aws_ecs_cluster.expense[0].name : null
}

output "ecs_expense_backend_service_name" {
  value = var.enabled ? aws_ecs_service.expense_backend[0].name : null
}

output "ecs_expense_frontend_service_name" {
  value = var.enabled ? aws_ecs_service.expense_frontend[0].name : null
}

