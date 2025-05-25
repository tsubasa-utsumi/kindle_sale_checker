# terraform/main.tf (役割明確化版)
provider "aws" {
  region = var.aws_region
}

# S3モジュール（フロントエンド用）
module "s3" {
  source       = "./modules/s3"
  bucket_name  = var.s3_bucket_name
  project_name = var.project_name
  environment  = var.environment
  
  # CloudFrontモジュールからの依存関係
  cloudfront_arn = module.cloudfront.distribution_arn
}

# DynamoDBモジュール
module "dynamodb" {
  source      = "./modules/dynamodb"
  table_name  = var.dynamodb_table_name
  project_name = var.project_name
  environment  = var.environment
}

# Cognitoモジュール（認証管理）
module "cognito" {
  source           = "./modules/cognito"
  project_name     = var.project_name
  environment      = var.environment
  
  # CloudFrontドメインを渡す
  cloudfront_domain = module.cloudfront.domain_name
}

# IAMモジュール（権限管理）
module "iam" {
  source           = "./modules/iam"
  project_name     = var.project_name
  environment      = var.environment
  dynamodb_arn     = module.dynamodb.table_arn
}

# 共通Lambda Layerモジュール（依存関係管理）
module "lambda_common_layer" {
  source       = "./modules/lambda_common_layer"
  project_name = var.project_name
  environment  = var.environment
  layer_name   = "common_dependencies"
  compatible_runtimes = ["python3.13"]
}

# Kindle Items APIモジュール（アイテム管理API）
module "kindle_items" {
  source                = "./modules/kindle_items"
  function_name         = var.lambda_function_name
  lambda_role_arn       = module.iam.lambda_role_arn
  dynamodb_table_name   = var.dynamodb_table_name
  project_name          = var.project_name
  environment           = var.environment
  layer_arn             = module.lambda_common_layer.layer_arn
}

# API Gatewayモジュール（Cognito認証対応）
module "api_gateway" {
  source                      = "./modules/api_gateway"
  api_name                    = var.api_name
  lambda_invoke_arn           = module.kindle_items.lambda_invoke_arn
  lambda_function_name        = module.kindle_items.lambda_function_name
  update_lambda_invoke_arn    = module.kindle_scraper.lambda_arn
  update_lambda_function_name = module.kindle_scraper.lambda_function_name
  project_name                = var.project_name
  environment                 = var.environment
  
  # Cognito認証パラメータ
  cognito_user_pool_id        = module.cognito.user_pool_id
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
}

# CloudFrontモジュール（CDN・API統合版）
module "cloudfront" {
  source                 = "./modules/cloudfront"
  project_name           = var.project_name
  environment            = var.environment
  
  # S3からの情報を渡す
  s3_bucket_domain_name  = module.s3.bucket_regional_domain_name
  s3_bucket_id           = module.s3.bucket_id
  s3_bucket_arn          = module.s3.bucket_arn
  
  # API Gatewayからの情報を渡す
  api_gateway_domain     = replace(replace(module.api_gateway.api_endpoint, "https://", ""), "/", "")
  api_gateway_id         = module.api_gateway.api_id
}

# Kindle Scraperモジュール（価格監視・通知）
module "kindle_scraper" {
  source                = "./modules/kindle_scraper"
  function_name         = var.lambda_scraper_name
  lambda_role_arn       = module.iam.lambda_role_arn
  dynamodb_table_name   = var.dynamodb_table_name
  project_name          = var.project_name
  environment           = var.environment
  layer_arn             = module.lambda_common_layer.layer_arn
  environment_variables = {
    LINE_CHANNEL_ACCESS_TOKEN = var.line_channel_access_token
    LINE_USER_ID              = var.line_user_id
    SALE_PERCENTAGE           = tostring(var.sale_percentage)
    SALE_PRICE                = tostring(var.sale_price)
  }
}