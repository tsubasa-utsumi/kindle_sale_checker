locals {
  # シークレット変数（変更時にはGitHubにコミットしないこと）
  # 代わりにterraform.tfvarsやAWS Parameterストアなどで管理することを推奨
  scraper_secrets = {
    LINE_CHANNEL_ACCESS_TOKEN = ""
    LINE_USER_ID              = ""
    SALE_PERCENTAGE           = "20"
    SALE_PRICE                = "500"
  }
}

# プロジェクト全体の変数を定義
variable "project_name" {
  description = "プロジェクト名"
  type        = string
  default     = "kindle_sale_checker"
}

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "環境（development, staging, production）"
  type        = string
  default     = "development"
}

variable "s3_bucket_name" {
  description = "フロントエンド用S3バケット名"
  type        = string
  default     = "kindle-sale-checker-frontend"
}

variable "dynamodb_table_name" {
  description = "DynamoDBテーブル名"
  type        = string
  default     = "KindleItems"
}

variable "lambda_function_name" {
  description = "items用Lambda関数名"
  type        = string
  default     = "kindle_sale_checker_api"
}

variable "api_name" {
  description = "API Gateway名"
  type        = string
  default     = "kindle-sale-checker-api"
}

variable "lambda_scraper_name" {
  description = "Kindleスクレイパー用Lambda関数名"
  type        = string
  default     = "kindle_scraper"
}

# シークレット変数（terraform.tfvarsファイルで上書きすること）
variable "line_channel_access_token" {
  description = "LINE Channel Access Token（機密情報）"
  type        = string
  default     = ""
  sensitive   = true
}

variable "line_user_id" {
  description = "LINE User ID（機密情報）"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sale_percentage" {
  description = "セール通知する割引率のしきい値（%）"
  type        = number
  default     = 20
}

variable "sale_price" {
  description = "セール通知する価格のしきい値（円）"
  type        = number
  default     = 500
}