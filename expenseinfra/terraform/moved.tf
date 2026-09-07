moved {
  from = module.runtime_ecs.aws_ssm_parameter.expense_image_release_seq[0]
  to   = module.shared.aws_ssm_parameter.expense_image_release_seq
}

moved {
  from = module.runtime_ecs.aws_ecr_repository.expense_backend[0]
  to   = module.shared.aws_ecr_repository.expense_backend
}

moved {
  from = module.runtime_ecs.aws_ecr_repository.expense_frontend[0]
  to   = module.shared.aws_ecr_repository.expense_frontend
}
