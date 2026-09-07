resource "random_id" "frontend_bucket_suffix" {
  count = var.enabled ? 1 : 0

  byte_length = 4
}

resource "aws_s3_bucket" "frontend" {
  count = var.enabled ? 1 : 0

  bucket        = "${var.project_name}-${random_id.frontend_bucket_suffix[0].hex}-web"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.frontend[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.frontend[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.frontend[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  count = var.enabled ? 1 : 0

  name                              = "${var.project_name}-web-oac-${random_id.frontend_bucket_suffix[0].hex}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  _expense_api_endpoint = try(aws_apigatewayv2_api.expense[0].api_endpoint, "")
  expense_index_html = var.enabled ? templatefile(var.expense_frontend_index_tpl, {
    api_base = local._expense_api_endpoint
  }) : ""
}

resource "aws_s3_object" "frontend_index" {
  count = var.enabled ? 1 : 0

  bucket        = aws_s3_bucket.frontend[0].id
  key           = "index.html"
  content_type  = "text/html; charset=utf-8"
  content       = local.expense_index_html
  etag          = md5(local.expense_index_html)
  cache_control = "max-age=0, must-revalidate"
}

resource "aws_s3_object" "frontend_favicon" {
  count = var.enabled ? 1 : 0

  bucket         = aws_s3_bucket.frontend[0].id
  key            = "favicon.ico"
  content_type   = "image/png"
  content_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
}

resource "aws_cloudfront_distribution" "frontend" {
  count = var.enabled ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.project_name} expense demo frontend"

  origin {
    domain_name              = aws_s3_bucket.frontend[0].bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend[0].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [aws_s3_object.frontend_index]
}

resource "aws_s3_bucket_policy" "frontend" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.frontend[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontRead"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.frontend[0].arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.frontend[0].arn
        }
      }
    }]
  })
}
