#!/bin/bash

# deploy_all.sh (レイヤー分離・動的設定版)

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名] [--auto-yes]"
  echo "  環境名: development, production など"
  echo "  --auto-yes: 確認プロンプトをスキップします"
  echo "  例: $0 development --auto-yes"
  echo "      確認なしでdevelopment環境にデプロイ"
  echo "  環境名を指定しない場合はデフォルト(production)環境にデプロイします"
  echo ""
  echo "注意: このスクリプトはLambda Layerをデプロイしません。"
  echo "      レイヤーを更新する場合は事前に ./deploy_layer.sh を実行してください。"
}

# デフォルト設定
ENV_NAME="production"
AUTO_YES=true

# 引数の処理
while [[ $# -gt 0 ]]; do
  case $1 in
    --auto-yes)
      AUTO_YES=true
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      if [[ -z "$ENV_NAME" || "$ENV_NAME" == "production" ]]; then
        ENV_NAME=$1
      fi
      shift
      ;;
  esac
done

echo "🚀 ${ENV_NAME} 環境への全体デプロイを開始します"
echo ""

# フロントエンドのチェック
if [ ! -d "frontend" ] || [ ! -f "frontend/package.json" ]; then
  echo "フロントエンドが適切に初期化されていません。初期化を実行します..."
  if [ ! -f "init_frontend.sh" ]; then
    echo "エラー: init_frontend.sh スクリプトが見つかりません。"
    exit 1
  fi
  
  chmod +x init_frontend.sh
  ./init_frontend.sh || { echo "フロントエンドの初期化に失敗しました"; exit 1; }
fi

# Cognito依存関係を追加
echo "📦 Cognito依存関係をインストールしています..."
cd frontend
if ! npm list amazon-cognito-identity-js >/dev/null 2>&1; then
  npm install amazon-cognito-identity-js || { echo "Cognito依存関係のインストールに失敗しました"; exit 1; }
fi
cd ..

# 環境に応じた変数ファイルを設定
VAR_FILE=""
if [ -f "terraform/terraform.tfvars" ]; then
  VAR_FILE="terraform/terraform.tfvars"
  echo "terraform.tfvarsを使用します（機密情報を含むファイル）"
else
  if [ -f "terraform/environments/${ENV_NAME}.tfvars" ]; then
    VAR_FILE="terraform/environments/${ENV_NAME}.tfvars"
    echo "${ENV_NAME}環境の変数ファイルを使用します"
  else
    echo "変数ファイルなしでデプロイします（デフォルト値が使用されます）"
  fi
fi

# Terraformインフラをデプロイ（Lambda Layer除く）
echo ""
echo "🏗️ Terraformインフラをデプロイしています..."
cd terraform
terraform init

# インフラ用のターゲット（Lambda Layer以外）
INFRA_TARGETS="-target=module.s3 -target=module.dynamodb -target=module.cognito -target=module.iam -target=module.api_gateway -target=module.cloudfront"

# プランファイル名を生成
PLAN_FILE="infra_deploy_plan.tfplan"

# 変数ファイルを確認
if [ -n "$VAR_FILE" ]; then
  # 相対パスを調整
  REL_VAR_FILE="../$VAR_FILE"
  
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    # プラン表示のみ（適用しない）
    terraform plan -var-file="$REL_VAR_FILE" $INFRA_TARGETS
    
    read -p "上記のインフラ計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "デプロイをキャンセルしました"
      exit 0
    fi
  fi
  
  # プラン生成とデプロイ実行
  terraform plan -var-file="$REL_VAR_FILE" $INFRA_TARGETS -out="$PLAN_FILE"
  terraform apply "$PLAN_FILE"
else
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    # プラン表示のみ（適用しない）
    terraform plan $INFRA_TARGETS
    
    read -p "上記のインフラ計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "デプロイをキャンセルしました"
      exit 0
    fi
  fi
  
  # プラン生成とデプロイ実行
  terraform plan $INFRA_TARGETS -out="$PLAN_FILE"
  terraform apply "$PLAN_FILE"
fi

# インフラデプロイ結果の確認
INFRA_RESULT=$?

# プランファイルの削除
rm -f "$PLAN_FILE"

if [ $INFRA_RESULT -ne 0 ]; then
  echo "❌ インフラのデプロイに失敗しました"
  exit 1
fi

echo "✅ インフラのデプロイが完了しました"

# 設定情報を取得
echo ""
echo "🔧 設定情報を取得しています..."
API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null)
API_GATEWAY_DIRECT=$(terraform output -raw api_gateway_endpoint 2>/dev/null)
COGNITO_USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null)
COGNITO_CLIENT_ID=$(terraform output -raw cognito_user_pool_client_id 2>/dev/null)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "ap-northeast-1")

# エンドポイント情報の表示
echo ""
echo "=== 📡 エンドポイント情報 ==="
if [ -n "$API_ENDPOINT" ]; then
  echo "🌐 CloudFront API Endpoint (推奨): $API_ENDPOINT"
else
  echo "⚠️ 警告: CloudFront APIエンドポイントの取得に失敗しました"
fi

if [ -n "$API_GATEWAY_DIRECT" ]; then
  echo "🛠️ API Gateway Direct (開発用): $API_GATEWAY_DIRECT"
else
  echo "⚠️ 警告: API Gateway直接エンドポイントの取得に失敗しました"
fi

if [ -z "$COGNITO_USER_POOL_ID" ] || [ -z "$COGNITO_CLIENT_ID" ]; then
  echo "⚠️ 警告: Cognito設定の取得に失敗しました"
  echo "フロントエンドの設定を手動で更新してください"
else
  echo "🔐 Cognito User Pool ID: $COGNITO_USER_POOL_ID"
  echo "🆔 Cognito Client ID: $COGNITO_CLIENT_ID"
fi
echo "🌍 AWS Region: $AWS_REGION"
echo "======================"
echo ""

cd ..

# Lambda関数をデプロイ
echo "⚡ Lambda関数をデプロイしています..."
AUTO_YES_PARAM=""
if [ "$AUTO_YES" = true ]; then
  AUTO_YES_PARAM="--auto-yes"
fi

./deploy_lambda_all.sh $ENV_NAME $AUTO_YES_PARAM || { echo "Lambda関数のデプロイに失敗しました"; exit 1; }

# フロントエンドのデプロイ
echo ""
echo "🎨 フロントエンドをデプロイしています..."
./deploy_frontend.sh $ENV_NAME $AUTO_YES_PARAM || { echo "フロントエンドのデプロイに失敗しました"; exit 1; }

echo ""
echo "🎉 ${ENV_NAME} 環境へのデプロイが完了しました"
echo ""

# 最終的なアクセス情報を表示
cd terraform
S3_WEBSITE=$(terraform output -raw website_endpoint 2>/dev/null)
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name 2>/dev/null)

echo "=== 🔗 アクセス情報 ==="
if [ -n "$S3_WEBSITE" ]; then
  echo "🌐 ウェブサイトURL: $S3_WEBSITE"
elif [ -n "$CLOUDFRONT_DOMAIN" ]; then
  echo "🌐 ウェブサイトURL: https://$CLOUDFRONT_DOMAIN"
else
  echo "⚠️ ウェブサイトURLの取得に失敗しました"
fi

echo ""
echo "=== 📱 API情報 ==="
if [ -n "$API_ENDPOINT" ]; then
  echo "🚀 CloudFront API Endpoint (推奨): $API_ENDPOINT"
  echo "   - HTTPS強制、高速、世界規模のCDN"
  echo "   - 本番環境で使用してください"
fi

if [ -n "$API_GATEWAY_DIRECT" ]; then
  echo "🛠️  API Gateway Direct (開発用): $API_GATEWAY_DIRECT"
  echo "   - 開発・デバッグ用"
fi

echo ""
echo "=== 🔐 認証情報 ==="
echo "- User Pool ID: $COGNITO_USER_POOL_ID"
echo "- Client ID: $COGNITO_CLIENT_ID"
echo "- Region: $AWS_REGION"

echo ""
echo "=== ⚠️ 重要な注意事項 ==="
echo "1. 📝 初回アクセス時は管理者ユーザーを作成してください:"
echo "   ./create_admin_user.sh admin@example.com"
echo ""
echo "2. ⏰ CloudFrontのキャッシュ反映には数分かかる場合があります"
echo ""
echo "3. 🚀 APIは CloudFront 経由でアクセスしてください（高速・安全）"
echo ""
echo "4. 🔧 Lambda Layerを更新する場合は別途実行してください:"
echo "   ./deploy_layer.sh $ENV_NAME"
echo ""
echo "5. 🔒 機密情報を設定する場合は terraform/terraform.tfvars を編集してください"
echo ""
echo "6. 📝 GitHub等にコミットする際は機密情報を含むファイルを除外してください"

cd ..