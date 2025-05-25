#!/bin/bash

# deploy_kindle_functions.sh - 全Kindle Lambda関数の統合デプロイスクリプト

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名] [--auto-yes]"
  echo "  環境名: development, production など"
  echo "  --auto-yes: 確認プロンプトをスキップします"
  echo "  例: $0 development --auto-yes"
  echo "      確認なしでdevelopment環境に全Kindle Lambda関数をデプロイ"
  echo "  環境名を指定しない場合はデフォルト(production)環境にデプロイします"
  echo ""
  echo "注意: このスクリプトはLambda Layerをデプロイしません。"
  echo "      レイヤーを更新する場合は事前に ./deploy_lambda_layer.sh を実行してください。"
  echo "      両Lambda関数（kindle_items、kindle_scraper）が独立して自動実行されます。"
}

# デフォルト設定
ENV_NAME="production"
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

echo "🚀 ${ENV_NAME} 環境への全Kindle Lambda関数デプロイを開始します"

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
    echo "⚠️ 変数ファイルが見つかりません。デフォルト値を使用します。"
    if [ "$AUTO_YES" = false ]; then
      read -p "続行しますか？ (y/n): " CONFIRM
      if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "❌ デプロイをキャンセルしました"
        exit 0
      fi
    fi
  fi
fi

# Kindle Items API Lambda関数のビルド
echo ""
echo "📦 Kindle Items API Lambda関数のビルド..."
if [ ! -f "build_kindle_items.sh" ]; then
  echo "❌ エラー: build_kindle_items.sh が見つかりません"
  exit 1
fi

chmod +x build_kindle_items.sh
./build_kindle_items.sh || { echo "❌ Kindle Items API Lambda関数のビルドに失敗しました"; exit 1; }

# Kindle Scraper Lambda関数のビルド
echo ""
echo "🕷️ Kindle Scraper Lambda関数のビルド..."
if [ ! -f "build_kindle_scraper.sh" ]; then
  echo "❌ エラー: build_kindle_scraper.sh が見つかりません"
  exit 1
fi

chmod +x build_kindle_scraper.sh
./build_kindle_scraper.sh || { echo "❌ Kindle Scraper Lambda関数のビルドに失敗しました"; exit 1; }

# ZIPファイルの存在とサイズ確認
if [ ! -f "terraform/lambda_function.zip" ]; then
  echo "❌ エラー: Kindle Items API Lambda関数のZIPファイルが見つかりません"
  exit 1
fi

if [ ! -f "terraform/lambda_scraper_function.zip" ]; then
  echo "❌ エラー: Kindle Scraper Lambda関数のZIPファイルが見つかりません"
  exit 1
fi

API_SIZE=$(du -k "terraform/lambda_function.zip" | cut -f1)
SCRAPER_SIZE=$(du -k "terraform/lambda_scraper_function.zip" | cut -f1)

if [ "$API_SIZE" -lt 1 ]; then
  echo "❌ エラー: Kindle Items API Lambda関数ZIPファイルが小さすぎます（空の可能性があります）"
  exit 1
fi

if [ "$SCRAPER_SIZE" -lt 1 ]; then
  echo "❌ エラー: Kindle Scraper Lambda関数ZIPファイルが小さすぎます（空の可能性があります）"
  exit 1
fi

echo ""
echo "📊 ビルド完了:"
echo "  📦 Kindle Items API関数サイズ: ${API_SIZE}KB"
echo "  🕷️ Kindle Scraper関数サイズ: ${SCRAPER_SIZE}KB"

# Terraformを適用
echo ""
echo "🏗️ Terraformを適用しています..."
cd terraform
terraform init

# プランファイル名を生成
PLAN_FILE="kindle_functions_deploy_plan.tfplan"

# Lambda関数のターゲット（レイヤーは除外）
LAMBDA_TARGETS="-target=module.kindle_items -target=module.kindle_scraper"

# 変数ファイルの有無によってコマンドを変更
if [ -n "$VAR_FILE" ]; then
  # 相対パスを調整
  REL_VAR_FILE="../${VAR_FILE}"
  
  # プラン表示してプランファイルに保存
  terraform plan -var-file="${REL_VAR_FILE}" $LAMBDA_TARGETS -out="$PLAN_FILE"
  
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    read -p "上記のKindle Lambda関数更新計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "❌ Kindle Lambda関数デプロイをキャンセルしました"
      rm -f "$PLAN_FILE"
      exit 0
    fi
  fi
  
  # プランファイルを使ってデプロイ実行
  terraform apply "$PLAN_FILE"
else
  # プラン表示してプランファイルに保存
  terraform plan $LAMBDA_TARGETS -out="$PLAN_FILE"
  
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    read -p "上記のKindle Lambda関数更新計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "❌ Kindle Lambda関数デプロイをキャンセルしました"
      rm -f "$PLAN_FILE"
      exit 0
    fi
  fi
  
  # プランファイルを使ってデプロイ実行
  terraform apply "$PLAN_FILE"
fi

# デプロイ結果の確認
DEPLOY_RESULT=$?

# プランファイルの削除
rm -f "$PLAN_FILE"

cd ..

if [ $DEPLOY_RESULT -eq 0 ]; then
  echo ""
  echo "✅ ${ENV_NAME} 環境への全Kindle Lambda関数デプロイが完了しました"
  
  # 関数情報の表示
  cd terraform
  API_FUNCTION_NAME=$(terraform output -raw lambda_function_name 2>/dev/null)
  SCRAPER_FUNCTION_NAME=$(terraform output -raw lambda_scraper_function_name 2>/dev/null)
  
  echo ""
  echo "⚡ デプロイされた関数:"
  if [ -n "$API_FUNCTION_NAME" ]; then
    echo "  📱 Kindle Items API関数: $API_FUNCTION_NAME"
    echo "     - 役割: アイテムのCRUD操作"
    echo "     - アクセス: API Gateway経由（Cognito認証必須）"
  fi
  if [ -n "$SCRAPER_FUNCTION_NAME" ]; then
    echo "  🕷️ Kindle Scraper関数: $SCRAPER_FUNCTION_NAME"
    echo "     - 役割: 価格監視・スクレイピング・通知"
    echo "     - 実行: 自動スケジューリング"
  fi
  
  echo ""
  echo "🧪 テスト方法:"
  echo "  📱 Kindle Items API関数のテスト: フロントエンドアプリからアクセス"
  echo "  🕷️ Kindle Scraper関数のテスト:"
  echo "     aws lambda invoke --function-name $SCRAPER_FUNCTION_NAME output.json"
  
  cd ..
else
  echo "❌ Kindle Lambda関数のデプロイに失敗しました"
  exit 1
fi

echo ""
echo "💡 次のステップ:"
echo "  📱 フロントエンドをデプロイ: ./deploy_frontend.sh ${ENV_NAME}"
echo "  🚀 全体をデプロイ: ./deploy_all.sh ${ENV_NAME}"
echo "  👤 管理者ユーザー作成: ./create_admin_user.sh admin@example.com"