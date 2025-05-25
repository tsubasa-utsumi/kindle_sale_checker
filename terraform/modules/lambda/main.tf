# Lambdaモジュール（レイヤー対応版）
variable "function_name" {
  description = "Lambda関数名"
  type        = string
}

variable "lambda_role_arn" {
  description = "Lambda実行ロールのARN"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDBテーブル名"
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

variable "layer_arn" {
  description = "Lambda Layer ARN"
  type        = string
}

# Lambda関数
resource "aws_lambda_function" "api" {
  function_name = var.function_name
  role          = var.lambda_role_arn
  handler       = "main.handler"
  runtime       = "python3.13"  # Python 3.13に更新
  timeout       = 30
  
  # デプロイパッケージのパス
  filename      = "${path.module}/../../lambda_function.zip"
  source_code_hash = filebase64sha256("${path.module}/../../lambda_function.zip")

  # Lambdaレイヤーを使用
  layers = [var.layer_arn]

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# 出力
output "lambda_function_name" {
  value = aws_lambda_function.api.function_name
}

output "lambda_invoke_arn" {
  value = aws_lambda_function.api.invoke_arn
}

output "lambda_arn" {
  value = aws_lambda_function.api.arn
}