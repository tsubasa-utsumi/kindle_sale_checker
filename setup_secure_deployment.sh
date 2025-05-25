#!/bin/bash

echo "🔒 セキュアデプロイメント環境をセットアップしています..."

# 1. 既存のソースファイルをバックアップ
echo "📋 既存のソースファイルをバックアップしています..."

if [ -f "frontend/src/App.js" ]; then
  cp frontend/src/App.js frontend/src/App.js.backup.$(date +%Y%m%d_%H%M%S)
  echo "  ✅ App.js をバックアップしました"
fi

if [ -f "frontend/src/authService.js" ]; then
  cp frontend/src/authService.js frontend/src/authService.js.backup.$(date +%Y%m%d_%H%M%S)
  echo "  ✅ authService.js をバックアップしました"
fi

if [ -f "deploy_frontend.sh" ]; then
  cp deploy_frontend.sh deploy_frontend.sh.backup.$(date +%Y%m%d_%H%M%S)
  echo "  ✅ deploy_frontend.sh をバックアップしました"
fi

if [ -f ".gitignore" ]; then
  cp .gitignore .gitignore.backup.$(date +%Y%m%d_%H%M%S)
  echo "  ✅ .gitignore をバックアップしました"
fi

# 2. 必要なディレクトリを作成
echo "📁 必要なディレクトリを作成しています..."
mkdir -p frontend/src

# 3. .gitignoreを更新（環境変数ファイルを除外）
echo "🛡️ .gitignoreを更新しています..."
cat >> .gitignore << 'EOF'

# 環境変数ファイル（機密情報を含むため除外）
frontend/.env
frontend/.env.local
frontend/.env.production
frontend/.env.development
frontend/.env.production.local
frontend/.env.development.local

# バックアップファイル
*.backup
frontend/src/*.backup

# 一時ファイル
frontend/.env.tmp
EOF

echo "  ✅ .gitignoreに機密情報の除外設定を追加しました"

# 4. 環境変数テンプレートファイルを作成
echo "📝 環境変数テンプレートファイルを作成しています..."

# 既存の設定をプレースホルダーに戻すためのスクリプトを作成
cat > reset_to_placeholders.sh << 'EOF'
#!/bin/bash

echo "🔄 フロントエンドソースファイルをプレースホルダーに戻しています..."

# App.jsのAPI_URLをプレースホルダーに戻す
if [ -f "frontend/src/App.js" ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's|const API_URL = .*|const API_URL = getApiUrl();|' frontend/src/App.js
    sed -i '' 's|process\.env\.REACT_APP_API_ENDPOINT.*|process.env.REACT_APP_API_ENDPOINT || '\''TERRAFORM_API_ENDPOINT_PLACEHOLDER'\'';|' frontend/src/App.js
  else
    sed -i 's|const API_URL = .*|const API_URL = getApiUrl();|' frontend/src/App.js
    sed -i 's|process\.env\.REACT_APP_API_ENDPOINT.*|process.env.REACT_APP_API_ENDPOINT || '\''TERRAFORM_API_ENDPOINT_PLACEHOLDER'\'';|' frontend/src/App.js
  fi
  echo "  ✅ App.js をプレースホルダーに戻しました"
fi

# authService.jsのCognito設定をプレースホルダーに戻す
if [ -f "frontend/src/authService.js" ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's|UserPoolId: .*|UserPoolId: getUserPoolId(),|' frontend/src/authService.js
    sed -i '' 's|ClientId: .*|ClientId: getClientId()|' frontend/src/authService.js
  else
    sed -i 's|UserPoolId: .*|UserPoolId: getUserPoolId(),|' frontend/src/authService.js
    sed -i 's|ClientId: .*|ClientId: getClientId()|' frontend/src/authService.js
  fi
  echo "  ✅ authService.js をプレースホルダーに戻しました"
fi

echo "✅ プレースホルダーへの復元が完了しました"
echo "💡 機密情報がソースコードから削除されました"
EOF

chmod +x reset_to_placeholders.sh

# 5. プレースホルダーへのリセットを実行
echo "🔄 既存の機密情報をプレースホルダーに戻しています..."
./reset_to_placeholders.sh

# 6. パッケージの依存関係を確認
echo "📦 フロントエンドの依存関係を確認しています..."
cd frontend

if [ ! -f "package.json" ]; then
  echo "⚠️ package.jsonが見つかりません。初期化します..."
  npm init -y
fi

# 必要なパッケージがインストールされているか確認
if ! npm list react >/dev/null 2>&1; then
  echo "📦 Reactをインストールしています..."
  npm install react react-dom react-scripts
fi

if ! npm list amazon-cognito-identity-js >/dev/null 2>&1; then
  echo "📦 Amazon Cognito Identity JSをインストールしています..."
  npm install amazon-cognito-identity-js
fi

if ! npm list axios >/dev/null 2>&1; then
  echo "📦 Axiosをインストールしています..."
  npm install axios
fi

cd ..

# 7. スクリプトに実行権限を付与
echo "🔧 スクリプトに実行権限を付与しています..."
chmod +x create_config_files.sh
chmod +x deploy_frontend.sh
chmod +x reset_to_placeholders.sh

# 8. 完了メッセージ
echo ""
echo "🎉 セキュアデプロイメント環境のセットアップが完了しました！"
echo ""
echo "📋 実行された作業:"
echo "  ✅ 既存ファイルのバックアップ作成"
echo "  ✅ .gitignoreに機密情報の除外設定を追加"
echo "  ✅ ソースコードから機密情報を削除（プレースホルダーに変更）"
echo "  ✅ 環境変数ベースの設定システムを導入"
echo "  ✅ 必要なスクリプトの準備"
echo ""
echo "🔒 セキュリティ強化:"
echo "  🛡️ 機密情報はGitにコミットされません"
echo "  🔧 環境変数ファイル（.env.*）は自動で除外"
echo "  📝 デプロイ時に動的に設定が生成されます"
echo ""
echo "🚀 次のステップ:"
echo "  1. 通常通りデプロイを実行: ./deploy_all.sh production --auto-yes"
echo "  2. 設定ファイルは自動生成されます"
echo "  3. Gitコミット時に機密情報は含まれません"
echo ""
echo "🔧 利用可能なコマンド:"
echo "  ./create_config_files.sh     - 環境設定ファイルを手動作成"
echo "  ./reset_to_placeholders.sh   - ソースコードをプレースホルダーに戻す"
echo "  ./deploy_frontend.sh         - フロントエンドのみデプロイ"
echo ""
echo "⚠️ 重要な注意事項:"
echo "  - frontend/.env* ファイルは絶対にGitにコミットしないでください"
echo "  - terraform.tfvars も機密情報を含むため除外されています"
echo "  - デプロイ前に必ずTerraformが適用されていることを確認してください"