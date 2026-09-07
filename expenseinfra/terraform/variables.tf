# Legacy path: Lambda + API Gateway + S3 + CloudFront.
# ECS path: ECR + Fargate + ALB (path /expenses|/months|/summary -> API; default -> static UI).
# Runtime selection is controlled by deployment_mode.

variable "deployment_mode" {
  description = "Runtime platform for expense app. Supported values: lambda, ecs, eks."
  type        = string
  default     = "lambda"

  validation {
    condition     = contains(["lambda", "ecs", "eks"], var.deployment_mode)
    error_message = "deployment_mode must be one of: lambda, ecs, eks."
  }
}

variable "ecr_expense_backend_repository_name" {
  description = "ECR repository name for the API Docker image. Leave null to use \"{project_name}-expense-backend\"."
  type        = string
  default     = null
  nullable    = true
}

variable "ecr_expense_frontend_repository_name" {
  description = "ECR repository name for the frontend Docker image. Leave null to use \"{project_name}-expense-frontend\"."
  type        = string
  default     = null
  nullable    = true
}

variable "aws_region" {
  description = "AWS region; ca-central-1 is common for Canada (Montreal)."
  type        = string
  default     = "ca-central-1"
}

variable "eks_vpc_cidr" {
  description = "CIDR block for the dedicated VPC used by EKS."
  type        = string
  default     = "10.40.0.0/16"
}

variable "eks_public_subnet_cidrs" {
  description = "Two public subnet CIDRs for the EKS VPC (one per AZ)."
  type        = list(string)
  default     = ["10.40.0.0/20", "10.40.16.0/20"]

  validation {
    condition     = length(var.eks_public_subnet_cidrs) == 2
    error_message = "eks_public_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "eks_private_subnet_cidrs" {
  description = "Two private subnet CIDRs for the EKS VPC (one per AZ)."
  type        = list(string)
  default     = ["10.40.128.0/20", "10.40.144.0/20"]

  validation {
    condition     = length(var.eks_private_subnet_cidrs) == 2
    error_message = "eks_private_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "project_name" {
  description = "Prefix for resource names (S3 bucket names: lowercase letters, digits, hyphens only)."
  type        = string
  default     = "<your-project-name>"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must start with a lowercase letter and contain only lowercase letters, digits, and hyphens (length about 2–21)."
  }
}

variable "budget_alert_email" {
  description = "Email for budget alerts (SNS subscription must be confirmed). Leave empty to skip SNS email subscription."
  type        = string
  default     = ""
}

variable "budget_monthly_usd" {
  description = "Monthly AWS cost budget limit in USD for 90%/100% notifications."
  type        = number
  default     = 20
}

variable "enable_aws_budget" {
  description = "Whether to create aws_budgets_budget (some accounts need Cost Explorer enabled first; set false if apply fails)."
  type        = bool
  default     = true
}

variable "eks_kubernetes_version" {
  description = "EKS Kubernetes version used when deployment_mode=eks."
  type        = string
  default     = "1.34"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for the default EKS managed node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "eks_node_desired_size" {
  description = "Desired node count for the default EKS managed node group."
  type        = number
  default     = 1
}

variable "eks_node_min_size" {
  description = "Minimum node count for the default EKS managed node group."
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Maximum node count for the default EKS managed node group."
  type        = number
  default     = 2
}

variable "eks_admin_principal_arn" {
  description = "IAM user or role ARN for cluster admin kubectl (human). Set via EKS_ADMIN_PRINCIPAL_ARN GitLab variable. Empty skips."
  type        = string
  default     = ""

  validation {
    condition     = var.eks_admin_principal_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/", var.eks_admin_principal_arn))
    error_message = "eks_admin_principal_arn must be empty or a valid IAM user/role ARN (arn:aws:iam::ACCOUNT:user/... or ...:role/...)."
  }
}

variable "eks_ci_principal_arn" {
  description = "IAM user or role ARN for CI automation kubectl (deploy-eks job). Set via EKS_CI_PRINCIPAL_ARN GitLab variable. Empty skips."
  type        = string
  default     = ""

  validation {
    condition     = var.eks_ci_principal_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/", var.eks_ci_principal_arn))
    error_message = "eks_ci_principal_arn must be empty or a valid IAM user/role ARN."
  }
}

