# CloudFrontモジュール（API統合版）
variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境（development, staging, production）"
  type        = string
}

variable "s3_bucket_domain_name" {
  description = "S3バケットの地域ドメイン名"
  type        = string
}

variable "s3_bucket_id" {
  description = "S3バケットID"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3バケットARN"
  type        = string
}

# API Gateway情報を追加
variable "api_gateway_domain" {
  description = "API Gatewayのドメイン名"
  type        = string
  default     = ""
}

variable "api_gateway_id" {
  description = "API Gateway ID"
  type        = string
  default     = ""
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "OAC for ${var.project_name} frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "frontend" {
  # S3オリジン（フロントエンド用）
  origin {
    domain_name              = var.s3_bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
    origin_id                = "S3-${var.s3_bucket_id}"
  }

  # API Gatewayオリジン（API用）
  dynamic "origin" {
    for_each = var.api_gateway_domain != "" ? [1] : []
    content {
      domain_name = var.api_gateway_domain
      origin_id   = "API-Gateway"
      
      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} ${var.environment} frontend and API"
  default_root_object = "index.html"

  # デフォルトキャッシュ動作（フロントエンド用）
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.s3_bucket_id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # API用のキャッシュ動作
  dynamic "ordered_cache_behavior" {
    for_each = var.api_gateway_domain != "" ? [1] : []
    content {
      path_pattern     = "/api/*"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD", "OPTIONS"]
      target_origin_id = "API-Gateway"

      # APIリクエスト用の設定
      forwarded_values {
        query_string = true
        headers      = ["Authorization", "Content-Type", "Accept", "Origin", "Referer"]
        
        cookies {
          forward = "none"
        }
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0     # APIレスポンスはキャッシュしない
      max_ttl                = 0     # APIレスポンスはキャッシュしない
      compress               = true
    }
  }

  # SPA用の404エラーハンドリング（すべて index.html にリダイレクト）
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
  }

  # 地理的制限なし
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL証明書設定（CloudFrontデフォルト）
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# 出力
output "distribution_id" {
  value = aws_cloudfront_distribution.frontend.id
}

output "domain_name" {
  value = aws_cloudfront_distribution.frontend.domain_name
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.frontend.arn
}

output "hosted_zone_id" {
  value = aws_cloudfront_distribution.frontend.hosted_zone_id
}

output "status" {
  value = aws_cloudfront_distribution.frontend.status
}

output "origin_access_control_id" {
  value = aws_cloudfront_origin_access_control.frontend.id
}

output "api_endpoint" {
  value = var.api_gateway_domain != "" ? "https://${aws_cloudfront_distribution.frontend.domain_name}/api" : ""
  description = "CloudFront経由のAPIエンドポイント"
}