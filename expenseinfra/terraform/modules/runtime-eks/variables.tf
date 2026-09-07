variable "enabled" {
  type = bool
}

variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "eks_vpc_cidr" {
  type        = string
  description = "CIDR block for the dedicated EKS VPC."
  default     = "10.40.0.0/16"
}

variable "eks_public_subnet_cidrs" {
  type        = list(string)
  description = "Two public subnet CIDRs (one per AZ)."
  default     = ["10.40.0.0/20", "10.40.16.0/20"]

  validation {
    condition     = length(var.eks_public_subnet_cidrs) == 2
    error_message = "eks_public_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "eks_private_subnet_cidrs" {
  type        = list(string)
  description = "Two private subnet CIDRs (one per AZ)."
  default     = ["10.40.128.0/20", "10.40.144.0/20"]

  validation {
    condition     = length(var.eks_private_subnet_cidrs) == 2
    error_message = "eks_private_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "eks_kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "eks_node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "eks_node_desired_size" {
  type    = number
  default = 1
}

variable "eks_node_min_size" {
  type    = number
  default = 1
}

variable "eks_node_max_size" {
  type    = number
  default = 2
}

variable "dynamodb_expenses_table_arn" {
  type        = string
  description = "Expense app DynamoDB table ARN; node role gets PutItem/Query/GetItem so backend pods can use IMDS credentials."
}

variable "eks_admin_principal_arn" {
  type        = string
  description = "IAM principal for EKS API access entry (human kubectl). Empty skips."
  default     = ""
}

variable "eks_ci_principal_arn" {
  type        = string
  description = "IAM principal for CI automation kubectl (deploy-eks job). Empty skips. If same as eks_admin_principal_arn, only one entry is created."
  default     = ""
}

