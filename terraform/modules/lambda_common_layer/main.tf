# Lambda Layerモジュール
variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境（development, staging, production）"
  type        = string
}

variable "layer_name" {
  description = "Lambda Layerの名前"
  type        = string
  default     = "common_dependencies"
}

variable "compatible_runtimes" {
  description = "互換性のあるLambdaランタイム"
  type        = list(string)
  default     = ["python3.13"]  # Python 3.13に更新
}

# Lambda Layer（共通レイヤー - API & スクレイパー両方の依存関係を含む）
resource "aws_lambda_layer_version" "dependencies" {
  layer_name          = "${var.project_name}_${var.layer_name}"
  filename            = "${path.module}/../../lambda_common_layer.zip"
  source_code_hash    = filebase64sha256("${path.module}/../../lambda_common_layer.zip")
  compatible_runtimes = var.compatible_runtimes

  description = "Common dependencies for ${var.project_name} Lambda functions"

  # レイヤーの内容がスタンダードであることを示すライセンス情報
  license_info = "MIT"
}

# 出力
output "layer_arn" {
  value = aws_lambda_layer_version.dependencies.arn
}

output "layer_name" {
  value = aws_lambda_layer_version.dependencies.layer_name
}