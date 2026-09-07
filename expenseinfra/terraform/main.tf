module "shared" {
  source = "./modules/shared"

  project_name                         = var.project_name
  budget_alert_email                   = var.budget_alert_email
  budget_monthly_usd                   = var.budget_monthly_usd
  enable_aws_budget                    = var.enable_aws_budget
  ecr_expense_backend_repository_name  = var.ecr_expense_backend_repository_name
  ecr_expense_frontend_repository_name = var.ecr_expense_frontend_repository_name
}

module "runtime_lambda" {
  source = "./modules/runtime-lambda"

  enabled                      = local.enable_expense_lambda
  project_name                 = var.project_name
  aws_region                   = var.aws_region
  expense_frontend_index_tpl   = local.expense_frontend_index_tpl
  expense_lambda_handler_py    = local.expense_lambda_handler_py
  dynamodb_expenses_table_name = module.shared.expenses_table_name
  dynamodb_expenses_table_arn  = module.shared.expenses_table_arn
}

module "runtime_ecs" {
  source = "./modules/runtime-ecs"

  enabled                             = local.enable_expense_ecs
  project_name                        = var.project_name
  aws_region                          = var.aws_region
  dynamodb_expenses_table_arn         = module.shared.expenses_table_arn
  ecr_expense_backend_repository_url  = module.shared.ecr_expense_backend_repository_url
  ecr_expense_frontend_repository_url = module.shared.ecr_expense_frontend_repository_url
}

module "runtime_eks" {
  source = "./modules/runtime-eks"

  enabled                     = local.enable_expense_eks
  project_name                = var.project_name
  aws_region                  = var.aws_region
  eks_vpc_cidr                = var.eks_vpc_cidr
  eks_public_subnet_cidrs     = var.eks_public_subnet_cidrs
  eks_private_subnet_cidrs    = var.eks_private_subnet_cidrs
  eks_kubernetes_version      = var.eks_kubernetes_version
  eks_node_instance_types     = var.eks_node_instance_types
  eks_node_desired_size       = var.eks_node_desired_size
  eks_node_min_size           = var.eks_node_min_size
  eks_node_max_size           = var.eks_node_max_size
  dynamodb_expenses_table_arn = module.shared.expenses_table_arn
  eks_admin_principal_arn     = var.eks_admin_principal_arn
  eks_ci_principal_arn        = var.eks_ci_principal_arn
}
