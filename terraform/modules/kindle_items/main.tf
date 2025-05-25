# Lambdaモジュール（kindle_items対応版）
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

# Lambda関数（Kindle Items API用）
resource "aws_lambda_function" "kindle_items" {
  function_name = var.function_name
  role          = var.lambda_role_arn
  handler       = "kindle_items.handler"  # main.handler から kindle_items.handler に変更
  runtime       = "python3.13"
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

  description = "Kindle Items API - アイテムの登録・取得・削除を行うAPI"

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Function    = "kindle_items_api"
  }
}

# 出力
output "lambda_function_name" {
  value = aws_lambda_function.kindle_items.function_name
}

output "lambda_invoke_arn" {
  value = aws_lambda_function.kindle_items.invoke_arn
}

output "lambda_arn" {
  value = aws_lambda_function.kindle_items.arn
}