#!/bin/bash

echo "Cognito設定をフロントエンドに反映しています..."

# Terraformから設定値を取得
if [ ! -d "terraform" ]; then
  echo "エラー: terraformディレクトリが見つかりません"
  exit 1
fi

cd terraform

USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null)
CLIENT_ID=$(terraform output -raw cognito_user_pool_client_id 2>/dev/null)

if [ -z "$USER_POOL_ID" ] || [ -z "$CLIENT_ID" ]; then
  echo "エラー: Cognito設定を取得できませんでした"
  echo "Terraformが正しくデプロイされているか確認してください"
  exit 1
fi

echo "取得した設定:"
echo "  User Pool ID: $USER_POOL_ID"
echo "  Client ID: $CLIENT_ID"

cd ..

# authService.jsの設定を更新
if [ ! -f "frontend/src/authService.js" ]; then
  echo "エラー: frontend/src/authService.js が見つかりません"
  exit 1
fi

echo "authService.jsを更新しています..."

# バックアップを作成
cp frontend/src/authService.js frontend/src/authService.js.backup

# 設定値を更新
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOSの場合
  sed -i '' "s|UserPoolId: '.*'|UserPoolId: '$USER_POOL_ID'|" frontend/src/authService.js
  sed -i '' "s|ClientId: '.*'|ClientId: '$CLIENT_ID'|" frontend/src/authService.js
else
  # Linuxの場合
  sed -i "s|UserPoolId: '.*'|UserPoolId: '$USER_POOL_ID'|" frontend/src/authService.js
  sed -i "s|ClientId: '.*'|ClientId: '$CLIENT_ID'|" frontend/src/authService.js
fi

echo "✅ Cognito設定の更新が完了しました"

# 設定が正しく更新されたか確認
echo ""
echo "更新後の設定:"
grep -A 2 "const poolData" frontend/src/authService.js

echo ""
echo "📝 次のステップ:"
echo "  ./deploy_frontend.sh production --auto-yes"
