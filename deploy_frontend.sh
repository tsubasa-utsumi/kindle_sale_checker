#!/bin/bash

# deploy_frontend.sh (動的設定版)

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名] [--auto-yes]"
  echo "  環境名: development, production など"
  echo "  --auto-yes: 確認プロンプトをスキップします"
  echo "  例: $0 development --auto-yes"
  echo "      確認なしでdevelopment環境のS3バケットにデプロイ"
  echo "  環境名を指定しない場合はデフォルト(production)環境にデプロイします"
}

# デフォルト環境
ENV_NAME="production"
S3_BUCKET="kindle-sale-checker-frontend"
AUTO_YES=false

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

# Terraformから設定を動的に取得する関数
get_terraform_config() {
  echo "🔧 Terraformから設定情報を取得しています..."
  
  if [ ! -d "terraform" ]; then
    echo "エラー: terraformディレクトリが見つかりません"
    exit 1
  fi
  
  cd terraform
  
  # 必要な設定値を取得
  API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null)
  USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null)
  CLIENT_ID=$(terraform output -raw cognito_user_pool_client_id 2>/dev/null)
  S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
  
  cd ..
  
  # 設定値の検証
  if [ -z "$API_ENDPOINT" ] || [ -z "$USER_POOL_ID" ] || [ -z "$CLIENT_ID" ] || [ -z "$S3_BUCKET" ]; then
    echo "エラー: Terraformから必要な設定を取得できませんでした"
    echo "取得された値:"
    echo "  API_ENDPOINT: $API_ENDPOINT"
    echo "  USER_POOL_ID: $USER_POOL_ID"
    echo "  CLIENT_ID: $CLIENT_ID"
    echo "  S3_BUCKET: $S3_BUCKET"
    echo ""
    echo "Terraformが正しくデプロイされているか確認してください"
    exit 1
  fi
  
  echo "✅ 設定情報を取得しました:"
  echo "  API Endpoint: $API_ENDPOINT"
  echo "  User Pool ID: $USER_POOL_ID"
  echo "  Client ID: $CLIENT_ID"
  echo "  S3 Bucket: $S3_BUCKET"
}

# フロントエンドの設定を更新する関数
update_frontend_config() {
  echo "🔧 フロントエンドの設定を更新しています..."
  
  # App.jsのAPI_URLを更新
  if [ -f "frontend/src/App.js" ]; then
    # macOSの場合とLinuxの場合で分岐
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOSの場合
      sed -i '' "s|const API_URL = '.*'|const API_URL = '$API_ENDPOINT'|" frontend/src/App.js
    else
      # Linuxの場合
      sed -i "s|const API_URL = '.*'|const API_URL = '$API_ENDPOINT'|" frontend/src/App.js
    fi
    
    echo "  ✓ App.jsのAPI_URLを更新: $API_ENDPOINT"
  else
    echo "  ⚠️ frontend/src/App.js が見つかりません"
  fi
  
  # authService.jsのCognito設定を更新
  if [ -f "frontend/src/authService.js" ]; then
    # macOSの場合とLinuxの場合で分岐
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOSの場合
      sed -i '' "s|UserPoolId: '.*'|UserPoolId: '$USER_POOL_ID'|" frontend/src/authService.js
      sed -i '' "s|ClientId: '.*'|ClientId: '$CLIENT_ID'|" frontend/src/authService.js
    else
      # Linuxの場合
      sed -i "s|UserPoolId: '.*'|UserPoolId: '$USER_POOL_ID'|" frontend/src/authService.js
      sed -i "s|ClientId: '.*'|ClientId: '$CLIENT_ID'|" frontend/src/authService.js
    fi
    
    echo "  ✓ authService.jsのCognito設定を更新"
  else
    echo "  ⚠️ frontend/src/authService.js が見つかりません"
  fi
}

echo "🚀 ${ENV_NAME} 環境の S3 バケット ${S3_BUCKET} にフロントエンドをデプロイします"

# Terraformから設定を取得
get_terraform_config

# フロントエンドディレクトリに移動
cd frontend || { echo "フロントエンドディレクトリが見つかりません"; exit 1; }

# package.jsonが存在するか確認
if [ ! -f "package.json" ]; then
  echo "package.jsonが見つかりません。frontend初期化スクリプトを実行してください。"
  echo "./init_frontend.sh"
  exit 1
fi

# node_modulesが存在するか確認
if [ ! -d "node_modules" ]; then
  echo "📦 node_modulesが見つかりません。依存関係をインストールします..."
  npm install || { echo "依存関係のインストールに失敗しました"; exit 1; }
fi

# Cognito依存関係の確認とインストール
if ! npm list amazon-cognito-identity-js >/dev/null 2>&1; then
  echo "📦 Cognito依存関係をインストールしています..."
  npm install amazon-cognito-identity-js || { echo "Cognito依存関係のインストールに失敗しました"; exit 1; }
fi

cd ..

# フロントエンドの設定を更新
update_frontend_config

cd frontend

# Reactアプリをビルド
echo "🏗️ Reactアプリをビルドしています..."
npm run build

# ビルドが成功したか確認
if [ ! -d "build" ]; then
  echo "ビルドに失敗しました。エラーを確認してください。"
  exit 1
fi

# エラーページの作成（存在しなければ）
if [ ! -f "build/error.html" ]; then
  echo "📄 エラーページを作成しています..."
  cp build/index.html build/error.html
fi

# S3バケットを確認
echo "☁️ S3バケット ${S3_BUCKET} を確認しています..."
if ! aws s3 ls "s3://${S3_BUCKET}" >/dev/null 2>&1; then
  echo "警告: S3バケット ${S3_BUCKET} が存在しないようです。"
  echo "まずTerraformを使ってインフラをデプロイしてください。"
  
  if [ "$AUTO_YES" = false ]; then
    read -p "それでも続行しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "デプロイをキャンセルしました"
      exit 0
    fi
  else
    echo "自動確認モードが有効なため、続行します..."
  fi
fi

# S3に同期（ACLオプションなし、バケットポリシーで権限管理）
echo "📁 ファイルをS3バケットに同期しています..."

# Step 1: 一括同期（シンプルアプローチ）
echo "  📁 全ファイルを同期中..."
aws s3 sync build/ "s3://${S3_BUCKET}" --delete

if [ $? -ne 0 ]; then
  echo "❌ S3への同期に失敗しました"
  exit 1
fi

echo "✅ ファイル同期完了"

# Step 2: ファイルタイプ別に最適なヘッダーを設定
echo "🎨 ファイルタイプ別のヘッダーを設定中..."

# HTMLファイル（キャッシュ無効）
if aws s3 ls "s3://${S3_BUCKET}/index.html" >/dev/null 2>&1; then
  echo "  📄 HTMLファイルの設定..."
  aws s3 cp "s3://${S3_BUCKET}/index.html" "s3://${S3_BUCKET}/index.html" \
    --metadata-directive REPLACE \
    --cache-control "max-age=0,no-cache,no-store,must-revalidate" \
    --content-type "text/html"
fi

if aws s3 ls "s3://${S3_BUCKET}/error.html" >/dev/null 2>&1; then
  aws s3 cp "s3://${S3_BUCKET}/error.html" "s3://${S3_BUCKET}/error.html" \
    --metadata-directive REPLACE \
    --cache-control "max-age=0,no-cache,no-store,must-revalidate" \
    --content-type "text/html"
fi

# CSSファイル（長期キャッシュ）
CSS_FILES=$(aws s3 ls "s3://${S3_BUCKET}/" --recursive | grep '\.css$' | awk '{print $4}')
if [ -n "$CSS_FILES" ]; then
  echo "  🎨 CSSファイルの設定..."
  while IFS= read -r file; do
    if [ -n "$file" ]; then
      aws s3 cp "s3://${S3_BUCKET}/$file" "s3://${S3_BUCKET}/$file" \
        --metadata-directive REPLACE \
        --cache-control "max-age=86400" \
        --content-type "text/css" >/dev/null 2>&1
    fi
  done <<< "$CSS_FILES"
fi

# JavaScriptファイル（長期キャッシュ）
JS_FILES=$(aws s3 ls "s3://${S3_BUCKET}/" --recursive | grep '\.js$' | awk '{print $4}')
if [ -n "$JS_FILES" ]; then
  echo "  ⚡ JavaScriptファイルの設定..."
  while IFS= read -r file; do
    if [ -n "$file" ]; then
      aws s3 cp "s3://${S3_BUCKET}/$file" "s3://${S3_BUCKET}/$file" \
        --metadata-directive REPLACE \
        --cache-control "max-age=86400" \
        --content-type "application/javascript" >/dev/null 2>&1
    fi
  done <<< "$JS_FILES"
fi

echo "✅ ヘッダー設定完了"

echo "✅ フロントエンドが S3 バケット ${S3_BUCKET} にデプロイされました"

# CloudFrontのディストリビューションIDを取得してキャッシュを無効化
echo "☁️ CloudFrontキャッシュを無効化しています..."
cd ../terraform
CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null)

if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
  echo "  CloudFront Distribution ID: $CLOUDFRONT_DISTRIBUTION_ID"
  aws cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
    --paths "/*" >/dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    echo "✅ CloudFrontキャッシュの無効化を開始しました（完了まで数分かかります）"
  else
    echo "⚠️  CloudFrontキャッシュの無効化に失敗しました"
  fi
else
  echo "⚠️  CloudFront Distribution IDが取得できませんでした"
fi

cd ../frontend

# 完了メッセージとアクセス情報の表示
echo ""
echo "🎉 デプロイ完了！"
echo "ウェブサイトにアクセスするには以下のURLを使用してください:"

cd ../terraform
WEBSITE_ENDPOINT=$(terraform output -raw website_endpoint 2>/dev/null)
if [ -n "$WEBSITE_ENDPOINT" ]; then
  echo "🔗 ${WEBSITE_ENDPOINT}"
else
  CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name 2>/dev/null)
  if [ -n "$CLOUDFRONT_DOMAIN" ]; then
    echo "🔗 https://$CLOUDFRONT_DOMAIN"
  else
    # フォールバック: S3ウェブサイトエンドポイント
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null)
    if [ -z "$AWS_REGION" ]; then
      AWS_REGION="ap-northeast-1"  # デフォルトリージョン
    fi
    echo "🔗 http://${S3_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
  fi
fi

echo ""
echo "📋 設定情報:"
echo "  🌐 API Endpoint: $API_ENDPOINT"
echo "  🔐 Cognito User Pool ID: $USER_POOL_ID"
echo "  🆔 Cognito Client ID: $CLIENT_ID"
echo ""
echo "💡 CloudFrontキャッシュの反映には数分かかる場合があります"
echo ""
echo "🚀 次のステップ:"
echo "  管理者ユーザーを作成するには: ./create_admin_user.sh admin@example.com"

cd ..