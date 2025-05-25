#!/bin/bash

# deploy_lambda_all.sh - 全Lambda関数の統合デプロイスクリプト

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名] [--auto-yes]"
  echo "  環境名: development, production など"
  echo "  --auto-yes: 確認プロンプトをスキップします"
  echo "  例: $0 development --auto-yes"
  echo "      確認なしでdevelopment環境に全Lambda関数をデプロイ"
  echo "  環境名を指定しない場合はデフォルト(production)環境にデプロイします"
  echo ""
  echo "注意: このスクリプトはLambda Layerをデプロイしません。"
  echo "      レイヤーを更新する場合は事前に ./deploy_layer.sh を実行してください。"
  echo "      スクレイパーは独立したLambda関数として自動実行されます。"
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

echo "${ENV_NAME} 環境への全Lambda関数デプロイを開始します"

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
    echo "変数ファイルが見つかりません。デフォルト値を使用します。"
    if [ "$AUTO_YES" = false ]; then
      read -p "続行しますか？ (y/n): " CONFIRM
      if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "デプロイをキャンセルしました"
        exit 0
      fi
    fi
  fi
fi

# API Lambda関数のビルド
echo "📦 API Lambda関数のビルド..."
if [ ! -f "build_lambda.sh" ]; then
  echo "API Lambda関数のビルドスクリプトを作成します..."
  cat > build_lambda.sh << 'EOF'
#!/bin/bash

echo "Lambda関数のデプロイパッケージを作成中..."

# プロジェクトのルートディレクトリを確認
if [ ! -d "lambda" ]; then
  echo "エラー: lambdaディレクトリが見つかりません。プロジェクトのルートディレクトリで実行してください。"
  exit 1
fi

# ビルドディレクトリを作成/クリア
rm -rf build
mkdir -p build

# Lambda関数のコードのみをコピー（依存関係はレイヤーに移行）
cp lambda/main.py build/

# ZIPファイル作成
cd build
zip -r lambda_function.zip main.py

# ZIPファイルの内容を確認
echo "ZIPファイルの内容:"
unzip -l lambda_function.zip

# ZIPファイルのサイズ確認
echo "ZIPファイルのサイズ: $(du -h lambda_function.zip)"

# 元のディレクトリに戻る
cd ..

# ZIPファイルをTerraformディレクトリにコピー
cp build/lambda_function.zip terraform/

echo "Lambda関数のデプロイパッケージが正常に作成されました: terraform/lambda_function.zip"
echo "サイズ: $(du -h terraform/lambda_function.zip | cut -f1)"
echo "依存ライブラリはLambdaレイヤーとして別途デプロイされます。"
EOF
  chmod +x build_lambda.sh
fi

chmod +x build_lambda.sh
./build_lambda.sh || { echo "API Lambda関数のビルドに失敗しました"; exit 1; }

# Scraper Lambda関数のビルド
echo "🕷️ Scraper Lambda関数のビルド..."
if [ ! -f "build_scraper_lambda.sh" ]; then
  echo "Scraper Lambda関数のビルドスクリプトを作成します..."
  cat > build_scraper_lambda.sh << 'EOF'
#!/bin/bash

echo "Kindle Scraper Lambda関数のデプロイパッケージを作成しています..."

# プロジェクトのルートディレクトリを確認
if [ ! -f "lambda/kindle_scraper.py" ]; then
  echo "エラー: lambda/kindle_scraper.py が見つかりません。"
  exit 1
fi

# ビルドディレクトリを作成/クリア
rm -rf build_scraper
mkdir -p build_scraper

# Lambda関数のコードのみをコピー（依存ライブラリはレイヤーに移行）
cp lambda/kindle_scraper.py build_scraper/

# シンプルなZIPファイル作成（依存ライブラリなし）
cd build_scraper
zip -r lambda_scraper_function.zip kindle_scraper.py

# ZIPファイルの内容を確認
echo "ZIPファイルの内容:"
unzip -l lambda_scraper_function.zip

# ZIPファイルのサイズを確認
echo "ZIPファイルのサイズ: $(du -h lambda_scraper_function.zip)"

# 元のディレクトリに戻る
cd ..

# ZIPファイルをterraformディレクトリにコピー
cp build_scraper/lambda_scraper_function.zip terraform/

echo "Kindle Scraper Lambda関数のデプロイパッケージが作成されました。"
echo "サイズ: $(du -h terraform/lambda_scraper_function.zip | cut -f1)"
echo "依存ライブラリはLambdaレイヤーとして別途デプロイされます。"
EOF
  chmod +x build_scraper_lambda.sh
fi

chmod +x build_scraper_lambda.sh
./build_scraper_lambda.sh || { echo "Scraper Lambda関数のビルドに失敗しました"; exit 1; }

# ZIPファイルの存在とサイズ確認
if [ ! -f "terraform/lambda_function.zip" ]; then
  echo "エラー: API Lambda関数のZIPファイルが見つかりません"
  exit 1
fi

if [ ! -f "terraform/lambda_scraper_function.zip" ]; then
  echo "エラー: Scraper Lambda関数のZIPファイルが見つかりません"
  exit 1
fi

API_SIZE=$(du -k "terraform/lambda_function.zip" | cut -f1)
SCRAPER_SIZE=$(du -k "terraform/lambda_scraper_function.zip" | cut -f1)

if [ "$API_SIZE" -lt 1 ]; then
  echo "エラー: API Lambda関数ZIPファイルが小さすぎます（空の可能性があります）"
  exit 1
fi

if [ "$SCRAPER_SIZE" -lt 1 ]; then
  echo "エラー: Scraper Lambda関数ZIPファイルが小さすぎます（空の可能性があります）"
  exit 1
fi

echo "📊 ビルド完了:"
echo "  API関数サイズ: ${API_SIZE}KB"
echo "  Scraper関数サイズ: ${SCRAPER_SIZE}KB"

# Terraformを適用
echo "🚀 Terraformを適用しています..."
cd terraform
terraform init

# プランファイル名を生成
PLAN_FILE="lambda_deploy_plan.tfplan"

# Lambda関数のターゲット（レイヤーは除外）
LAMBDA_TARGETS="-target=module.lambda -target=module.lambda_scraper"

# 変数ファイルの有無によってコマンドを変更
if [ -n "$VAR_FILE" ]; then
  # 相対パスを調整
  REL_VAR_FILE="../${VAR_FILE}"
  
  # プラン表示してプランファイルに保存
  terraform plan -var-file="${REL_VAR_FILE}" $LAMBDA_TARGETS -out="$PLAN_FILE"
  
  # 確認プロンプト
  if [ "$AUTO_YES" = false ]; then
    read -p "上記のLambda関数更新計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "Lambda関数デプロイをキャンセルしました"
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
    read -p "上記のLambda関数更新計画を適用しますか？ (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      echo "Lambda関数デプロイをキャンセルしました"
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
  echo "✅ ${ENV_NAME} 環境への全Lambda関数デプロイが完了しました"
  
  # 関数情報の表示
  cd terraform
  API_FUNCTION_NAME=$(terraform output -raw lambda_function_name 2>/dev/null)
  SCRAPER_FUNCTION_NAME=$(terraform output -raw lambda_scraper_function_name 2>/dev/null)
  
  echo ""
  echo "⚡ デプロイされた関数:"
  if [ -n "$API_FUNCTION_NAME" ]; then
    echo "  📱 API関数: $API_FUNCTION_NAME"
  fi
  if [ -n "$SCRAPER_FUNCTION_NAME" ]; then
    echo "  🕷️ Scraper関数: $SCRAPER_FUNCTION_NAME"
  fi
  
  echo ""
  echo "🧪 テスト方法:"
  echo "  API関数のテスト: フロントエンドアプリからアクセス"
  echo "  Scraper関数のテスト: aws lambda invoke --function-name $SCRAPER_FUNCTION_NAME output.json"
  
  cd ..
else
  echo "❌ Lambda関数のデプロイに失敗しました"
  exit 1
fi

echo ""
echo "💡 次のステップ:"
echo "  フロントエンドをデプロイするには: ./deploy_frontend.sh ${ENV_NAME}"
echo "  全体をデプロイするには: ./deploy_all.sh ${ENV_NAME}"