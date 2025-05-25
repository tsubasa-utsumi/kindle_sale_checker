#!/bin/bash

# deploy_layer.sh - Lambda Layerのデプロイ専用スクリプト

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名] [--auto-yes]"
  echo "  環境名: development, production など"
  echo "  --auto-yes: 確認プロンプトをスキップします"
  echo "  例: $0 development --auto-yes"
  echo "      確認なしでdevelopment環境にLambda Layerをデプロイ"
  echo "  環境名を指定しない場合はデフォルト(production)環境にデプロイします"
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

echo "${ENV_NAME} 環境へのLambda Layerデプロイを開始します"

# 環境に応じた変数ファイルの確認
VAR_FILE=""
if [ -f "terraform/terraform.tfvars" ]; then
  VAR_FILE="terraform/terraform.tfvars"
  echo "terraform.tfvarsを使用します（機密情報を含むファイル）"
else
  if [ -f "terraform/environments/${ENV_NAME}.tfvars" ]; then
    VAR_FILE="terraform/environments/${ENV_NAME}.tfvars"
    echo "${ENV_NAME}環境の変数ファイルを使用します"
  fi
fi

# 共通Lambdaレイヤーを作成
echo "共通Lambdaレイヤーを作成しています..."
if [ ! -f "create_common_layer.sh" ]; then
  echo "エラー: create_common_layer.sh が見つかりません"
  exit 1
fi

chmod +x create_common_layer.sh
./create_common_layer.sh || { echo "共通レイヤーの作成に失敗しました"; exit 1; }

# レイヤーZIPファイルの存在確認
if [ ! -f "terraform/lambda_common_layer.zip" ]; then
  echo "エラー: レイヤーZIPファイルが見つかりません"
  exit 1
fi

LAYER_SIZE=$(du -k "terraform/lambda_common_layer.zip" | cut -f1)
if [ "$LAYER_SIZE" -lt 10 ]; then
  echo "エラー: レイヤーZIPファイルが小さすぎます（空の可能性があります）"
  exit 1
fi

echo "レイヤーサイズ: ${LAYER_SIZE}KB"

# Terraformを適用
echo "Terraformを適用しています..."
cd terraform
terraform init

# プランファイル名を生成
PLAN_FILE="layer_deploy_plan.tfplan"

# 変数ファイルの有無によってコマンドを変更
if [ -n "$VAR_FILE" ]; then
  # 相対パスを調整
  REL_VAR_FILE="../${VAR_FILE}"
  
  # プラン表示してプランファイルに保存
  terraform plan -var-file="${REL_VAR_FILE}" -target=module.lambda_layer -out="$PLAN_FILE"
  
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    read -p "上記のレイヤー更新計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "レイヤーデプロイをキャンセルしました"
      rm -f "$PLAN_FILE"
      exit 0
    fi
  fi
  
  # プランファイルを使ってデプロイ実行
  terraform apply "$PLAN_FILE"
else
  # プラン表示してプランファイルに保存
  terraform plan -target=module.lambda_layer -out="$PLAN_FILE"
  
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    read -p "上記のレイヤー更新計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "レイヤーデプロイをキャンセルしました"
      rm -f "$PLAN_FILE"
      exit 0
    fi
  fi
  
  # プランファイルを使ってデプロイ実行
  terraform apply "$PLAN_FILE"
fi

# プランファイルの削除
rm -f "$PLAN_FILE"

if [ $? -eq 0 ]; then
  echo "✅ ${ENV_NAME} 環境へのLambda Layerデプロイが完了しました"
  
  # レイヤー情報の表示
  LAYER_ARN=$(terraform output -raw lambda_layer_arn 2>/dev/null)
  if [ -n "$LAYER_ARN" ]; then
    echo ""
    echo "📦 レイヤー情報:"
    echo "  ARN: $LAYER_ARN"
  fi
  
  echo ""
  echo "💡 次のステップ:"
  echo "  Lambda関数をデプロイするには: ./deploy_lambda_all.sh ${ENV_NAME}"
  echo "  全体をデプロイするには: ./deploy_all.sh ${ENV_NAME}"
else
  echo "❌ Lambda Layerのデプロイに失敗しました"
  exit 1
fi

cd ..