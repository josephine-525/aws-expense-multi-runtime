# Application source lives in the expenseapp repo (frontend/ + backend/).
# Default: sibling of expenseinfra repo — ../../expenseapp from this module (terraform/).
# Override in CI or monorepos: TF_VAR_expenseapp_repo_path=/abs/path/to/expenseapp

variable "expenseapp_repo_path" {
  type        = string
  description = "Absolute path to expenseapp repo root (must contain frontend/index.html.tpl and backend/lambda/handler.py). Leave empty to use ../../expenseapp (sibling of expenseinfra/)."
  default     = ""
}

locals {
  expenseapp_root            = var.expenseapp_repo_path != "" ? var.expenseapp_repo_path : abspath("${path.root}/../../expenseapp")
  expense_frontend_index_tpl = abspath("${local.expenseapp_root}/frontend/index.html.tpl")
  expense_lambda_handler_py  = abspath("${local.expenseapp_root}/backend/lambda/handler.py")
}
