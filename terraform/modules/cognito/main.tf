# terraform/modules/cognito/main.tf
variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "environment" {
  description = "環境（development, staging, production）"
  type        = string
}

variable "cloudfront_domain" {
  description = "CloudFrontのドメイン（HTTPS用）"
  type        = string
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-user-pool"

  # パスワードポリシー
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  # ユーザー名の設定（emailでもログイン可能）
  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]

  # アカウント回復設定
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # トークンの有効期限設定はUser Pool Clientで行う

  # ユーザー属性
  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
    mutable            = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # OAuth設定
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  # コールバックURL（HTTPS必須 + 開発環境用localhost）
  callback_urls = [
    "https://${var.cloudfront_domain}",
    "https://${var.cloudfront_domain}/",
    "https://${var.cloudfront_domain}/callback",
    "http://localhost:3000",
    "http://localhost:3000/",
    "http://localhost:3000/callback"
  ]

  logout_urls = [
    "https://${var.cloudfront_domain}",
    "https://${var.cloudfront_domain}/",
    "http://localhost:3000",
    "http://localhost:3000/"
  ]

  # 認証フロー
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # CSRFプロテクション
  generate_secret = false

  # トークンの有効期限（最大値に設定）
  refresh_token_validity = 3650  # 10年（実質無期限）
  access_token_validity  = 1440  # 24時間（分単位）
  id_token_validity      = 1440  # 24時間（分単位）

  token_validity_units {
    refresh_token = "days"
    access_token  = "minutes"
    id_token      = "minutes"
  }

  # PKCE有効化（セキュリティ向上）
  prevent_user_existence_errors = "ENABLED"
}

# Cognito Identity Pool
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name      = "${var.project_name}-${var.environment}-identity-pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Identity Pool Role Attachment
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated" = aws_iam_role.authenticated.arn
  }
}

# 認証済みユーザー用のIAMロール
resource "aws_iam_role" "authenticated" {
  name = "${var.project_name}-${var.environment}-cognito-authenticated"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# 認証済みユーザー用のポリシー
resource "aws_iam_role_policy" "authenticated" {
  name = "${var.project_name}-${var.environment}-cognito-authenticated-policy"
  role = aws_iam_role.authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-identity:GetCredentialsForIdentity",
          "cognito-identity:GetId"
        ]
        Resource = "*"
      }
    ]
  })
}

# 出力
output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "identity_pool_id" {
  value = aws_cognito_identity_pool.main.id
}

output "user_pool_domain" {
  value = aws_cognito_user_pool.main.domain
}

output "user_pool_endpoint" {
  value = aws_cognito_user_pool.main.endpoint
}