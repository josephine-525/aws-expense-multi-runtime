output "aws_region" {
  value = var.aws_region
}

output "dynamodb_expenses_table_name" {
  description = "Expense demo table (user_id + expense_id)."
  value       = module.shared.expenses_table_name
}

output "expense_api_endpoint" {
  description = "Legacy: API Gateway base URL. ECS: same host as expense_app_url (paths /expenses, /months, /summary)."
  value       = module.runtime_lambda.expense_api_endpoint
}

output "cloudfront_domain_name" {
  description = "Legacy frontend hostname (S3/CloudFront). Null unless deployment_mode=lambda."
  value       = module.runtime_lambda.cloudfront_domain_name
}

output "cloudfront_url" {
  description = "Legacy frontend HTTPS URL. Null unless deployment_mode=lambda."
  value       = module.runtime_lambda.cloudfront_url
}

output "expense_alb_dns_name" {
  description = "Application Load Balancer DNS (ECS mode). Open http://<this> in a browser."
  value       = module.runtime_ecs.expense_alb_dns_name
}

output "expense_app_url" {
  description = "Expense UI + API on one host (ECS). HTTP only unless you add HTTPS on the ALB."
  value       = module.runtime_ecs.expense_app_url
}

output "ecr_expense_backend_repository_url" {
  description = "ECR URL for the API image (push :latest from CI)."
  value       = module.shared.ecr_expense_backend_repository_url
}

output "ecr_expense_frontend_repository_url" {
  description = "docker push for nginx UI image; build with API_BASE empty (same-origin)."
  value       = module.shared.ecr_expense_frontend_repository_url
}

output "ecs_cluster_name" {
  value = module.runtime_ecs.ecs_cluster_name
}

output "ecs_expense_backend_service_name" {
  value = module.runtime_ecs.ecs_expense_backend_service_name
}

output "ecs_expense_frontend_service_name" {
  value = module.runtime_ecs.ecs_expense_frontend_service_name
}

output "expense_image_release_ssm_parameter_name" {
  description = "SSM parameter GitLab CI increments for v001-style tags (GetParameter + PutParameter IAM required)."
  value       = module.shared.expense_image_release_ssm_parameter_name
}

output "sns_budget_topic_arn" {
  description = "SNS topic for monthly budget alerts (email subscriptions must be confirmed)."
  value       = module.shared.sns_budget_topic_arn
}

output "eks_cluster_name" {
  description = "EKS cluster name when deployment_mode=eks."
  value       = module.runtime_eks.eks_cluster_name
}

output "eks_status" {
  description = "EKS cluster status when deployment_mode=eks."
  value       = module.runtime_eks.eks_status
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint when deployment_mode=eks."
  value       = module.runtime_eks.eks_cluster_endpoint
}

output "eks_node_group_name" {
  description = "Default EKS managed node group name when deployment_mode=eks."
  value       = module.runtime_eks.eks_node_group_name
}

output "eks_node_group_apps_name" {
  description = "Apps EKS managed node group name when deployment_mode=eks."
  value       = module.runtime_eks.eks_node_group_apps_name
}

output "eks_expense_backend_irsa_role_arn" {
  description = "IRSA role ARN for the expense-backend ServiceAccount. Also published to SSM at /{project_name}/expense/eks-expense-backend-role-arn — expenseapp CI reads it from there, no manual CI variable needed."
  value       = module.runtime_eks.eks_expense_backend_irsa_role_arn
}

output "eks_cluster_additional_security_group_id" {
  description = "EKS additional control-plane SG when deployment_mode=eks."
  value       = module.runtime_eks.eks_cluster_additional_security_group_id
}

output "eks_cluster_primary_security_group_id" {
  description = "EKS cluster primary SG when deployment_mode=eks."
  value       = module.runtime_eks.eks_cluster_primary_security_group_id
}

output "eks_node_security_group_id" {
  description = "EKS worker node SG when deployment_mode=eks."
  value       = module.runtime_eks.eks_node_security_group_id
}

output "aws_lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller. Also published to SSM at /{project_name}/expense/eks-aws-lbc-role-arn — expenseapp CI reads it from there, no manual CI variable needed."
  value       = module.runtime_eks.aws_lbc_role_arn
}

output "eks_alb_security_group_id" {
  description = "ALB SG ID when deployment_mode=eks. Also published to SSM at /{project_name}/expense/eks-alb-security-group-id — expenseapp CI reads it from there, no manual CI variable needed."
  value       = module.runtime_eks.eks_alb_security_group_id
}
