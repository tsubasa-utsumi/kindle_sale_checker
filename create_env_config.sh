#!/bin/bash

echo "環境設定ファイルを作成しています..."

# Terraformから設定値を取得
if [ ! -d "terraform" ]; then
  echo "エラー: terraformディレクトリが見つかりません"
  exit 1
fi

cd terraform

USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null)
CLIENT_ID=$(terraform output -raw cognito_user_pool_client_id 2>/dev/null)
API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null)

if [ -z "$USER_POOL_ID" ] || [ -z "$CLIENT_ID" ]; then
  echo "エラー: Cognito設定を取得できませんでした"
  echo "Terraformが正しくデプロイされているか確認してください"
  exit 1
fi

cd ..

# .env.productionファイルを作成
echo "本番環境用の環境変数ファイルを作成しています..."
cat > frontend/.env.production << ENVEOF
# Cognito設定（本番環境）
REACT_APP_COGNITO_USER_POOL_ID=$USER_POOL_ID
REACT_APP_COGNITO_CLIENT_ID=$CLIENT_ID
REACT_APP_API_ENDPOINT=$API_ENDPOINT

# デバッグ設定
REACT_APP_DEBUG_MODE=false
GENERATE_SOURCEMAP=false
ENVEOF

# .env.developmentファイルを作成（開発用）
echo "開発環境用の環境変数ファイルを作成しています..."
cat > frontend/.env.development << ENVEOF
# Cognito設定（開発環境）
REACT_APP_COGNITO_USER_POOL_ID=$USER_POOL_ID
REACT_APP_COGNITO_CLIENT_ID=$CLIENT_ID
REACT_APP_API_ENDPOINT=$API_ENDPOINT

# デバッグ設定
REACT_APP_DEBUG_MODE=true
GENERATE_SOURCEMAP=true
ENVEOF

echo "✅ 環境設定ファイルが作成されました:"
echo "  - frontend/.env.production"
echo "  - frontend/.env.development"
echo ""
echo "設定値:"
echo "  User Pool ID: $USER_POOL_ID"
echo "  Client ID: $CLIENT_ID"
echo "  API Endpoint: $API_ENDPOINT"
