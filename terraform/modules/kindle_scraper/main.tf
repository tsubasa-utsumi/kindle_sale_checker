# Lambda Scraperモジュール（レイヤー対応版）
variable "function_name" {
  description = "Lambda Scraper関数名"
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

variable "environment_variables" {
  description = "Lambda関数の環境変数"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# Lambda関数
resource "aws_lambda_function" "scraper" {
  function_name = var.function_name
  role          = var.lambda_role_arn
  handler       = "kindle_scraper.handler"
  runtime       = "python3.13"  # Python 3.13に更新
  timeout       = 600  # スクレイピングに十分な時間（10分）
  memory_size   = 256  # メモリサイズを増加
  
  # デプロイパッケージのパス
  filename      = "${path.module}/../../lambda_scraper_function.zip"
  source_code_hash = filebase64sha256("${path.module}/../../lambda_scraper_function.zip")

  # Lambdaレイヤーを使用
  layers = [var.layer_arn]

  environment {
    variables = merge(
      {
        DYNAMODB_TABLE = var.dynamodb_table_name,
      },
      var.environment_variables
    )
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# 出力
output "lambda_function_name" {
  value = aws_lambda_function.scraper.function_name
}

output "lambda_arn" {
  value = aws_lambda_function.scraper.arn
}