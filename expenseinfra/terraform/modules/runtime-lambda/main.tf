data "aws_partition" "current" {}

data "archive_file" "expense_lambda_zip" {
  count = var.enabled ? 1 : 0

  type        = "zip"
  source_file = var.expense_lambda_handler_py
  output_path = "${path.root}/lambda/expense_api/bundle.zip"
}

resource "aws_iam_role" "expense_lambda" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-expense-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "expense_lambda_basic" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.expense_lambda[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "expense_ddb" {
  count = var.enabled ? 1 : 0

  name = "ddb-expenses"
  role = aws_iam_role.expense_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:Query", "dynamodb:GetItem"]
      Resource = var.dynamodb_expenses_table_arn
    }]
  })
}

resource "aws_lambda_function" "expense_api" {
  count = var.enabled ? 1 : 0

  function_name    = "${var.project_name}-expense-api"
  role             = aws_iam_role.expense_lambda[0].arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.expense_lambda_zip[0].output_path
  source_code_hash = data.archive_file.expense_lambda_zip[0].output_base64sha256

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_expenses_table_name
    }
  }
}
