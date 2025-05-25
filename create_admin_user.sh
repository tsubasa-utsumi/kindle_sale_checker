#!/bin/bash

# create_admin_user.sh - Cognito管理者ユーザー作成スクリプト

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 <メールアドレス> [一時パスワード]"
  echo "  例: $0 admin@example.com"
  echo "      $0 admin@example.com TempPass123!"
  echo ""
  echo "一時パスワードを指定しない場合は自動生成されます。"
  echo "Terraformデプロイ後に実行してください。"
}

# 引数チェック
if [ $# -lt 1 ]; then
  show_usage
  exit 1
fi

EMAIL=$1
TEMP_PASSWORD=${2:-$(openssl rand -base64 12)Aa1!}

echo "管理者ユーザーを作成しています..."
echo "メールアドレス: $EMAIL"
echo "一時パスワード: $TEMP_PASSWORD"

# Terraformから User Pool ID を取得
if [ ! -d "terraform" ]; then
  echo "エラー: terraformディレクトリが見つかりません"
  echo "プロジェクトルートで実行してください"
  exit 1
fi

cd terraform

USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null)

if [ -z "$USER_POOL_ID" ]; then
  echo "エラー: User Pool IDを取得できませんでした"
  echo "Terraformが正しくデプロイされているか確認してください"
  exit 1
fi

echo "User Pool ID: $USER_POOL_ID"

# 管理者ユーザーを作成
echo "ユーザーを作成中..."

# メールアドレスからユーザー名を生成（email aliasの場合は別のユーザー名が必要）
USERNAME=$(echo "$EMAIL" | sed 's/@/_at_/' | sed 's/\./_/g')
echo "生成されたユーザー名: $USERNAME"

aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "$USERNAME" \
  --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
  --temporary-password "$TEMP_PASSWORD" \
  --message-action SUPPRESS

if [ $? -eq 0 ]; then
  echo "✅ 管理者ユーザーの作成が完了しました"
  echo ""
  echo "ログイン情報:"
  echo "  ユーザー名: $USERNAME"
  echo "  メールアドレス: $EMAIL"
  echo "  一時パスワード: $TEMP_PASSWORD"
  echo ""
  echo "注意事項:"
  echo "  1. ログイン時はメールアドレス($EMAIL)またはユーザー名($USERNAME)のどちらでもログイン可能です"
  echo "  2. 初回ログイン時に新しいパスワードの設定が求められます"
  echo "  3. パスワードは8文字以上で英数字を含む必要があります"
  echo "  4. 一時パスワードは安全に管理してください"
  echo ""
  echo "ログインURL: http://$(terraform output -raw website_endpoint 2>/dev/null)"
else
  echo "❌ ユーザーの作成に失敗しました"
  echo ""
  echo "トラブルシューティング:"
  echo "  1. AWS CLIが正しく設定されているか確認してください"
  echo "  2. 適切なIAM権限があるか確認してください"
  echo "  3. 同じユーザー名のユーザーが既に存在しないか確認してください"
  
  # 既存ユーザーの確認
  echo ""
  echo "既存ユーザーを確認しています..."
  aws cognito-idp admin-get-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$USERNAME" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo "⚠️  同じユーザー名のユーザーが既に存在します"
    echo "既存ユーザーを削除してから再実行するか、別のメールアドレスを使用してください"
    echo ""
    echo "既存ユーザーを削除する場合:"
    echo "  aws cognito-idp admin-delete-user --user-pool-id $USER_POOL_ID --username $USERNAME"
  fi
  
  exit 1
fi

cd -