# S3モジュール（CloudFront分離版）
variable "bucket_name" {
  description = "S3バケット名"
  type        = string
}

variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境（development, staging, production）"
  type        = string
}

variable "cloudfront_arn" {
  description = "CloudFront Distribution ARN"
  type        = string
}

# S3バケット - フロントエンドのホスティング用
resource "aws_s3_bucket" "frontend" {
  bucket = var.bucket_name

  tags = {
    Name        = "${var.project_name}-frontend"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3バケットのパブリックアクセス設定（ポリシーのみ許可）
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true   # ACLをブロック
  block_public_policy     = false  # バケットポリシーは許可
  ignore_public_acls      = true   # ACLを無視
  restrict_public_buckets = false  # パブリックバケットポリシーを許可
}

# S3バケットのCORS設定
resource "aws_s3_bucket_cors_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# S3バケットのウェブサイト設定
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"  # SPAのため404も index.html にリダイレクト
  }
}

# S3バケットポリシー（CloudFrontとCLIデプロイ用のアクセスを許可）
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = var.cloudfront_arn
          }
        }
      },
      {
        Sid       = "AllowCurrentAccountCLIAccess"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.frontend.arn}",
          "${aws_s3_bucket.frontend.arn}/*"
        ]
      },
      {
        Sid       = "AllowPublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.frontend
  ]
}

# ダミーオブジェクト
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index_placeholder.html"
  content      = "<html><head><title>Placeholder</title></head><body><p>This is a placeholder. Actual content will be deployed via deploy_frontend.sh script.</p></body></html>"
  content_type = "text/html"

  depends_on = [
    aws_s3_bucket_website_configuration.frontend
  ]
}

# 出力
output "bucket_name" {
  value = aws_s3_bucket.frontend.id
}

output "bucket_id" {
  value = aws_s3_bucket.frontend.id
}

output "bucket_arn" {
  value = aws_s3_bucket.frontend.arn
}

output "bucket_regional_domain_name" {
  value = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "website_endpoint" {
  value = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "website_domain" {
  value = aws_s3_bucket_website_configuration.frontend.website_domain
}