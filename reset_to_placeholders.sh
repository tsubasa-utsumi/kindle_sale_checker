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
