# terraform/modules/api_gateway/main.tf (ドメイン出力追加版)
# API Gatewayモジュール（Cognito認証付き）
variable "api_name" {
  description = "API Gateway名"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "Lambda関数の呼び出しARN"
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda関数名"
  type        = string
}

variable "update_lambda_invoke_arn" {
  description = "Update Lambda関数の呼び出しARN"
  type        = string
}

variable "update_lambda_function_name" {
  description = "Update Lambda関数名"
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

# Cognito認証用の変数を追加
variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  type        = string
}

# API Gateway
resource "aws_apigatewayv2_api" "api" {
  name          = var.api_name
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito JWT Authorizer
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-cognito-authorizer"

  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = "https://cognito-idp.ap-northeast-1.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# items用のLambda統合
resource "aws_apigatewayv2_integration" "items" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = var.lambda_invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# update用のLambda統合
resource "aws_apigatewayv2_integration" "update" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = var.update_lambda_invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# itemsルート（Cognito認証必須）
resource "aws_apigatewayv2_route" "items_get" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /api/items"
  target    = "integrations/${aws_apigatewayv2_integration.items.id}"
  
  authorization_type = "JWT"
  authorizer_id     = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "items_post" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /api/items"
  target    = "integrations/${aws_apigatewayv2_integration.items.id}"
  
  authorization_type = "JWT"
  authorizer_id     = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "items_by_id" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /api/items/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.items.id}"
  
  authorization_type = "JWT"
  authorizer_id     = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "items_delete" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "DELETE /api/items/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.items.id}"
  
  authorization_type = "JWT"
  authorizer_id     = aws_apigatewayv2_authorizer.cognito.id
}

# updateルート（Cognito認証必須）
resource "aws_apigatewayv2_route" "update_post" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /api/update"
  target    = "integrations/${aws_apigatewayv2_integration.update.id}"
  
  authorization_type = "JWT"
  authorizer_id     = aws_apigatewayv2_authorizer.cognito.id
}

# Lambda実行権限（items用）
resource "aws_lambda_permission" "items" {
  statement_id  = "AllowAPIGatewayInvokeItems"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# Lambda実行権限（update用）
resource "aws_lambda_permission" "update" {
  statement_id  = "AllowAPIGatewayInvokeUpdate"
  action        = "lambda:InvokeFunction"
  function_name = var.update_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# 出力
output "api_endpoint" {
  value = aws_apigatewayv2_stage.api.invoke_url
}

output "api_domain_name" {
  value = replace(replace(aws_apigatewayv2_stage.api.invoke_url, "https://", ""), "/", "")
  description = "API Gatewayのドメイン名（CloudFron用）"
}

output "api_id" {
  value = aws_apigatewayv2_api.api.id
}

output "authorizer_id" {
  value = aws_apigatewayv2_authorizer.cognito.id
}

output "available_routes" {
  value = {
    items = [
      "GET /items (認証必須)",
      "POST /items (認証必須)", 
      "GET /items/{id} (認証必須)",
      "DELETE /items/{id} (認証必須)"
    ]
    update = [
      "POST /update (認証必須)"
    ]
  }
  description = "利用可能なAPIルート一覧（すべて認証必須）"
}