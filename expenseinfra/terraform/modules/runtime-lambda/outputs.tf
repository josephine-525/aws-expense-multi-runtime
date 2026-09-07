output "expense_api_endpoint" {
  value = var.enabled ? aws_apigatewayv2_api.expense[0].api_endpoint : null
}

output "cloudfront_domain_name" {
  value = var.enabled ? aws_cloudfront_distribution.frontend[0].domain_name : null
}

output "cloudfront_url" {
  value = var.enabled ? "https://${aws_cloudfront_distribution.frontend[0].domain_name}" : null
}
