#!/bin/bash

# deploy_all.sh (ビルド統合版)

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名] [--auto-yes] [--skip-layer]"
  echo "  環境名: development, production など"
  echo "  --auto-yes: 確認プロンプトをスキップします"
  echo "  --skip-layer: Lambda Layerのビルド・デプロイをスキップします"
  echo "  例: $0 development --auto-yes"
  echo "      確認なしでdevelopment環境にデプロイ"
  echo "  環境名を指定しない場合はデフォルト(production)環境にデプロイします"
  echo ""
  echo "このスクリプトは以下を自動実行します:"
  echo "  1. Lambda Common Layerのビルド・デプロイ"
  echo "  2. Kindle Lambda関数のビルド"
  echo "  3. インフラストラクチャのデプロイ"
  echo "  4. Lambda関数のデプロイ"
  echo "  5. フロントエンドのデプロイ"
}

# デフォルト設定
ENV_NAME="production"
AUTO_YES=true
SKIP_LAYER=false

# 引数の処理
while [[ $# -gt 0 ]]; do
  case $1 in
    --auto-yes)
      AUTO_YES=true
      shift
      ;;
    --skip-layer)
      SKIP_LAYER=true
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
  echo "📦 フロントエンドが適切に初期化されていません。初期化を実行します..."
  if [ ! -f "init_frontend.sh" ]; then
    echo "❌ エラー: init_frontend.sh スクリプトが見つかりません。"
    exit 1
  fi
  
  chmod +x init_frontend.sh
  ./init_frontend.sh || { echo "❌ フロントエンドの初期化に失敗しました"; exit 1; }
fi

# Cognito依存関係を追加
echo "📦 Cognito依存関係をインストールしています..."
cd frontend
if ! npm list amazon-cognito-identity-js >/dev/null 2>&1; then
  npm install amazon-cognito-identity-js || { echo "❌ Cognito依存関係のインストールに失敗しました"; exit 1; }
fi
cd ..

# 環境に応じた変数ファイルを設定
VAR_FILE=""
if [ -f "terraform/terraform.tfvars" ]; then
  VAR_FILE="terraform/terraform.tfvars"
  echo "📝 terraform.tfvarsを使用します（機密情報を含むファイル）"
else
  if [ -f "terraform/environments/${ENV_NAME}.tfvars" ]; then
    VAR_FILE="terraform/environments/${ENV_NAME}.tfvars"
    echo "📝 ${ENV_NAME}環境の変数ファイルを使用します"
  else
    echo "⚠️ 変数ファイルなしでデプロイします（デフォルト値が使用されます）"
  fi
fi

# =============================================================================
# 1. Lambda Common Layerのビルド・デプロイ
# =============================================================================
if [ "$SKIP_LAYER" = false ]; then
  echo ""
  echo "📦 Lambda Common Layerをビルド・デプロイしています..."
  
  # レイヤーのビルド
  if [ ! -f "build_lambda_layer.sh" ]; then
    echo "❌ エラー: build_lambda_layer.sh が見つかりません"
    exit 1
  fi
  
  chmod +x build_lambda_layer.sh
  ./build_lambda_layer.sh || { echo "❌ Lambda Common Layerのビルドに失敗しました"; exit 1; }
  
  # レイヤーのデプロイ
  if [ ! -f "deploy_lambda_layer.sh" ]; then
    echo "❌ エラー: deploy_lambda_layer.sh が見つかりません"
    exit 1
  fi
  
  chmod +x deploy_lambda_layer.sh
  AUTO_YES_PARAM=""
  if [ "$AUTO_YES" = true ]; then
    AUTO_YES_PARAM="--auto-yes"
  fi
  
  ./deploy_lambda_layer.sh $ENV_NAME $AUTO_YES_PARAM || { echo "❌ Lambda Common Layerのデプロイに失敗しました"; exit 1; }
  
  echo "✅ Lambda Common Layerのビルド・デプロイが完了しました"
else
  echo "⏭️ Lambda Layerのビルド・デプロイをスキップします"
fi

# =============================================================================
# 2. Kindle Lambda関数のビルド
# =============================================================================
echo ""
echo "🔨 Kindle Lambda関数をビルドしています..."

# Kindle Items APIのビルド
echo "📦 Kindle Items APIをビルド中..."
if [ ! -f "build_kindle_items.sh" ]; then
  echo "❌ エラー: build_kindle_items.sh が見つかりません"
  exit 1
fi

chmod +x build_kindle_items.sh
./build_kindle_items.sh || { echo "❌ Kindle Items APIのビルドに失敗しました"; exit 1; }

# Kindle Scraperのビルド
echo "🕷️ Kindle Scraperをビルド中..."
if [ ! -f "build_kindle_scraper.sh" ]; then
  echo "❌ エラー: build_kindle_scraper.sh が見つかりません"
  exit 1
fi

chmod +x build_kindle_scraper.sh
./build_kindle_scraper.sh || { echo "❌ Kindle Scraperのビルドに失敗しました"; exit 1; }

echo "✅ 全Kindle Lambda関数のビルドが完了しました"

# ZIPファイルの存在確認
echo ""
echo "📋 ビルド結果を確認中..."
if [ ! -f "terraform/lambda_function.zip" ]; then
  echo "❌ エラー: Kindle Items API ZIPファイルが見つかりません"
  exit 1
fi

if [ ! -f "terraform/lambda_scraper_function.zip" ]; then
  echo "❌ エラー: Kindle Scraper ZIPファイルが見つかりません"
  exit 1
fi

if [ "$SKIP_LAYER" = false ] && [ ! -f "terraform/lambda_common_layer.zip" ]; then
  echo "❌ エラー: Lambda Common Layer ZIPファイルが見つかりません"
  exit 1
fi

# ファイルサイズの表示
KINDLE_ITEMS_SIZE=$(du -h "terraform/lambda_function.zip" | cut -f1)
KINDLE_SCRAPER_SIZE=$(du -h "terraform/lambda_scraper_function.zip" | cut -f1)

echo "📊 ビルド成果物:"
echo "  📦 Kindle Items API: $KINDLE_ITEMS_SIZE"
echo "  🕷️ Kindle Scraper: $KINDLE_SCRAPER_SIZE"

if [ "$SKIP_LAYER" = false ] && [ -f "terraform/lambda_common_layer.zip" ]; then
  LAMBDA_LAYER_SIZE=$(du -h "terraform/lambda_common_layer.zip" | cut -f1)
  echo "  📚 Lambda Common Layer: $LAMBDA_LAYER_SIZE"
fi

# =============================================================================
# 3. Terraformインフラをデプロイ（Lambda Layer除く）
# =============================================================================
echo ""
echo "🏗️ Terraformインフラをデプロイしています..."
cd terraform
terraform init

# インフラ用のターゲット（Lambda関数とLayerは後でデプロイ）
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
      echo "❌ デプロイをキャンセルしました"
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
      echo "❌ デプロイをキャンセルしました"
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

# =============================================================================
# 4. Kindle Lambda関数のデプロイ
# =============================================================================
echo ""
echo "⚡ Kindle Lambda関数をデプロイしています..."

# Lambda関数のターゲット
LAMBDA_TARGETS="-target=module.kindle_items -target=module.kindle_scraper"

# プランファイル名を生成
LAMBDA_PLAN_FILE="lambda_deploy_plan.tfplan"

# 変数ファイルの有無によってコマンドを変更
if [ -n "$VAR_FILE" ]; then
  # 相対パスを調整
  REL_VAR_FILE="../${VAR_FILE}"
  
  # プラン表示してプランファイルに保存
  terraform plan -var-file="${REL_VAR_FILE}" $LAMBDA_TARGETS -out="$LAMBDA_PLAN_FILE"
  
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    read -p "上記のKindle Lambda関数更新計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "❌ Kindle Lambda関数デプロイをキャンセルしました"
      rm -f "$LAMBDA_PLAN_FILE"
      cd ..
      exit 0
    fi
  fi
  
  # プランファイルを使ってデプロイ実行
  terraform apply "$LAMBDA_PLAN_FILE"
else
  # プラン表示してプランファイルに保存
  terraform plan $LAMBDA_TARGETS -out="$LAMBDA_PLAN_FILE"
  
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    read -p "上記のKindle Lambda関数更新計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "❌ Kindle Lambda関数デプロイをキャンセルしました"
      rm -f "$LAMBDA_PLAN_FILE"
      cd ..
      exit 0
    fi
  fi
  
  # プランファイルを使ってデプロイ実行
  terraform apply "$LAMBDA_PLAN_FILE"
fi

# Lambda関数デプロイ結果の確認
LAMBDA_RESULT=$?

# プランファイルの削除
rm -f "$LAMBDA_PLAN_FILE"

if [ $LAMBDA_RESULT -ne 0 ]; then
  echo "❌ Kindle Lambda関数のデプロイに失敗しました"
  cd ..
  exit 1
fi

echo "✅ Kindle Lambda関数のデプロイが完了しました"

# =============================================================================
# 5. 設定情報を取得
# =============================================================================
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

# =============================================================================
# 6. フロントエンドのデプロイ
# =============================================================================
echo "🎨 フロントエンドをデプロイしています..."
AUTO_YES_PARAM=""
if [ "$AUTO_YES" = true ]; then
  AUTO_YES_PARAM="--auto-yes"
fi

./deploy_frontend.sh $ENV_NAME $AUTO_YES_PARAM || { echo "❌ フロントエンドのデプロイに失敗しました"; exit 1; }

# =============================================================================
# 7. 完了メッセージ
# =============================================================================
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
echo "=== 📱 Kindle Lambda関数情報 ==="
KINDLE_ITEMS_FUNCTION=$(terraform output -raw lambda_function_name 2>/dev/null)
KINDLE_SCRAPER_FUNCTION=$(terraform output -raw lambda_scraper_function_name 2>/dev/null)

if [ -n "$KINDLE_ITEMS_FUNCTION" ]; then
  echo "📦 Kindle Items API: $KINDLE_ITEMS_FUNCTION"
  echo "   - 役割: アイテムのCRUD操作"
  echo "   - アクセス: API Gateway経由（認証必須）"
fi

if [ -n "$KINDLE_SCRAPER_FUNCTION" ]; then
  echo "🕷️ Kindle Scraper: $KINDLE_SCRAPER_FUNCTION"
  echo "   - 役割: 価格監視・スクレイピング・通知"
  echo "   - 実行: 自動スケジューリング"
fi

echo ""
echo "=== 📡 API情報 ==="
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
echo "=== 📊 デプロイ済みコンポーネント ==="
echo "✅ Lambda Common Layer: 共通依存関係"
echo "✅ Kindle Items API: アイテム管理"
echo "✅ Kindle Scraper: 価格監視・通知"
echo "✅ S3 + CloudFront: フロントエンド配信"
echo "✅ DynamoDB: データストレージ"
echo "✅ API Gateway: 認証付きAPI"
echo "✅ Cognito: ユーザー認証"

echo ""
echo "=== ⚠️ 重要な注意事項 ==="
echo "1. 📝 初回アクセス時は管理者ユーザーを作成してください:"
echo "   ./create_admin_user.sh admin@example.com"
echo ""
echo "2. ⏰ CloudFrontのキャッシュ反映には数分かかる場合があります"
echo ""
echo "3. 🚀 APIは CloudFront 経由でアクセスしてください（高速・安全）"
echo ""
echo "4. 🔧 個別更新時のコマンド:"
echo "   - Lambda関数のみ: ./deploy_kindle_functions.sh $ENV_NAME"
echo "   - Lambda Layerのみ: ./deploy_lambda_layer.sh $ENV_NAME"
echo "   - フロントエンドのみ: ./deploy_frontend.sh $ENV_NAME"
echo ""
echo "5. 🔒 機密情報を設定する場合は terraform/terraform.tfvars を編集してください"
echo ""
echo "6. 📝 GitHub等にコミットする際は機密情報を含むファイルを除外してください"

cd ..