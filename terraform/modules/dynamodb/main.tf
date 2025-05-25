# DynamoDBモジュール
variable "table_name" {
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

# DynamoDB テーブル
resource "aws_dynamodb_table" "items" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-dynamodb"
    Environment = var.environment
    Project     = var.project_name
  }
}

# 出力
output "table_name" {
  value = aws_dynamodb_table.items.name
}

output "table_arn" {
  value = aws_dynamodb_table.items.arn
}