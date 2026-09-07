resource "aws_apigatewayv2_api" "expense" {
  count = var.enabled ? 1 : 0

  name          = "${var.project_name}-expense-http"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "expense_lambda" {
  count = var.enabled ? 1 : 0

  api_id                 = aws_apigatewayv2_api.expense[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.expense_api[0].invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "expense_get" {
  count = var.enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.expense[0].id
  route_key = "GET /expenses"
  target    = "integrations/${aws_apigatewayv2_integration.expense_lambda[0].id}"
}

resource "aws_apigatewayv2_route" "expense_post" {
  count = var.enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.expense[0].id
  route_key = "POST /expenses"
  target    = "integrations/${aws_apigatewayv2_integration.expense_lambda[0].id}"
}

resource "aws_apigatewayv2_route" "months_get" {
  count = var.enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.expense[0].id
  route_key = "GET /months"
  target    = "integrations/${aws_apigatewayv2_integration.expense_lambda[0].id}"
}

resource "aws_apigatewayv2_route" "months_post" {
  count = var.enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.expense[0].id
  route_key = "POST /months"
  target    = "integrations/${aws_apigatewayv2_integration.expense_lambda[0].id}"
}

resource "aws_apigatewayv2_route" "summary_get" {
  count = var.enabled ? 1 : 0

  api_id    = aws_apigatewayv2_api.expense[0].id
  route_key = "GET /summary"
  target    = "integrations/${aws_apigatewayv2_integration.expense_lambda[0].id}"
}

resource "aws_apigatewayv2_stage" "expense_default" {
  count = var.enabled ? 1 : 0

  api_id      = aws_apigatewayv2_api.expense[0].id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "expense_apigw" {
  count = var.enabled ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.expense_api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.expense[0].execution_arn}/*/*"
}
