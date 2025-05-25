# terraform/outputs.tf (CloudFront API統合版)
# 出力値の定義

# API Gateway直接アクセス（開発用）
output "api_gateway_endpoint" {
  value       = module.api_gateway.api_endpoint
  description = "API Gateway直接エンドポイントURL（開発用）"
}

# CloudFront経由のAPIエンドポイント（本番推奨）
output "api_endpoint" {
  value       = "https://${module.cloudfront.domain_name}/api"
  description = "CloudFront経由のAPIエンドポイントURL（本番用）"
}

output "available_routes" {
  value       = module.api_gateway.available_routes
  description = "利用可能なAPIルート一覧（すべて認証必須）"
}

# CloudFront関連
output "website_endpoint" {
  value       = "https://${module.cloudfront.domain_name}"
  description = "CloudFront HTTPS ウェブサイトエンドポイント"
}

output "cloudfront_distribution_id" {
  value       = module.cloudfront.distribution_id
  description = "CloudFront Distribution ID"
}

output "cloudfront_domain_name" {
  value       = module.cloudfront.domain_name
  description = "CloudFrontドメイン名"
}

output "cloudfront_status" {
  value       = module.cloudfront.status
  description = "CloudFront Distribution Status"
}

# S3関連
output "s3_website_endpoint" {
  value       = module.s3.website_endpoint
  description = "S3ウェブサイトエンドポイント（開発用）"
}

output "s3_bucket_name" {
  value       = module.s3.bucket_name
  description = "S3バケット名"
}

# DynamoDB関連
output "dynamodb_table_name" {
  value       = module.dynamodb.table_name
  description = "DynamoDBテーブル名"
}

# Lambda関連
output "lambda_function_name" {
  value       = module.lambda.lambda_function_name
  description = "items用Lambda関数名"
}

output "lambda_scraper_function_name" {
  value       = module.lambda_scraper.lambda_function_name
  description = "scraper用Lambda関数名（updateルートでも使用）"
}

# Cognito関連
output "cognito_user_pool_id" {
  value       = module.cognito.user_pool_id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = module.cognito.user_pool_client_id
  description = "Cognito User Pool Client ID"
}

output "cognito_identity_pool_id" {
  value       = module.cognito.identity_pool_id
  description = "Cognito Identity Pool ID"
}

# フロントエンド設定情報
output "frontend_configuration" {
  value = {
    api_endpoint                = "https://${module.cloudfront.domain_name}/api"
    api_gateway_direct          = module.api_gateway.api_endpoint
    cognito_user_pool_id        = module.cognito.user_pool_id
    cognito_user_pool_client_id = module.cognito.user_pool_client_id
    cognito_identity_pool_id    = module.cognito.identity_pool_id
    aws_region                  = var.aws_region
    cloudfront_domain           = module.cloudfront.domain_name
    s3_bucket_name              = module.s3.bucket_name
  }
  description = "フロントエンド用の設定情報"
}

# AWS リージョン
output "aws_region" {
  value       = var.aws_region
  description = "AWS リージョン"
}

# エンドポイント使い分けガイド
output "endpoint_usage_guide" {
  value = {
    production = "https://${module.cloudfront.domain_name}/api - CloudFront経由（推奨、高速、HTTPS強制）"
    development = "${module.api_gateway.api_endpoint} - API Gateway直接（開発用、デバッグ用）"
    frontend = "https://${module.cloudfront.domain_name} - フロントエンドアプリケーション"
  }
  description = "エンドポイントの使い分けガイド"
}