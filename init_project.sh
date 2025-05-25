#!/bin/bash

echo "Kindle Sale Checker プロジェクトを初期化しています..."

# プロジェクトのディレクトリ構造を作成
mkdir -p terraform/modules/s3
mkdir -p terraform/modules/dynamodb
mkdir -p terraform/modules/iam
mkdir -p terraform/modules/lambda
mkdir -p terraform/modules/api_gateway
mkdir -p terraform/environments
mkdir -p lambda
mkdir -p frontend/public
mkdir -p frontend/src

echo "プロジェクト構造を作成しています..."

# 既存のファイルを移動する関数
move_if_exists() {
  if [ -f "$1" ] && [ ! -f "$2" ]; then
    mkdir -p "$(dirname "$2")"
    mv "$1" "$2"
    echo "ファイル移動: $1 -> $2"
  fi
}

# 既存ファイルがなければ作成する関数
create_if_not_exists() {
  if [ ! -f "$1" ]; then
    mkdir -p "$(dirname "$1")"
    touch "$1"
    echo "ファイル作成: $1"
  else
    echo "ファイル存在: $1 (既存ファイルを保持します)"
  fi
}

# 既存のTerraformファイルをterraformフォルダに移動
move_if_exists "main.tf" "terraform/main.tf"
move_if_exists "variables.tf" "terraform/variables.tf"
move_if_exists "outputs.tf" "terraform/outputs.tf"

# modules内の既存ファイルをterraform/modules以下に移動
if [ -d "modules" ]; then
  for module in s3 dynamodb iam lambda api_gateway; do
    if [ -d "modules/$module" ]; then
      for file in modules/$module/*; do
        if [ -f "$file" ]; then
          basename=$(basename "$file")
          move_if_exists "$file" "terraform/modules/$module/$basename"
        fi
      done
    fi
  done
  
  # 空になったmodulesディレクトリを削除
  find modules -type d -empty -delete
  if [ -d modules ] && [ -z "$(ls -A modules)" ]; then
    rmdir modules
    echo "空のmodulesディレクトリを削除しました"
  fi
fi

# Terraformモジュールファイルの作成
create_if_not_exists "terraform/modules/s3/main.tf"
create_if_not_exists "terraform/modules/dynamodb/main.tf"
create_if_not_exists "terraform/modules/iam/main.tf"
create_if_not_exists "terraform/modules/lambda/main.tf"
create_if_not_exists "terraform/modules/api_gateway/main.tf"

# Terraformルートファイルの作成
create_if_not_exists "terraform/main.tf"
create_if_not_exists "terraform/variables.tf"
create_if_not_exists "terraform/outputs.tf"

# サンプル環境変数ファイルの作成
if [ ! -f "terraform/environments/development.tfvars" ]; then
  cat > terraform/environments/development.tfvars << 'EOF'
# 開発環境用変数
environment = "development"
project_name = "kindle_sale_checker_dev"
s3_bucket_name = "kindle-sale-checker-dev-frontend"
dynamodb_table_name = "KindleItems_Dev"
EOF
  echo "ファイル作成: terraform/environments/development.tfvars"
fi

if [ ! -f "terraform/environments/production.tfvars" ]; then
  cat > terraform/environments/production.tfvars << 'EOF'
# 本番環境用変数
environment = "production"
project_name = "kindle_sale_checker"
s3_bucket_name = "kindle-sale-checker-frontend"
dynamodb_table_name = "KindleItems"
EOF
  echo "ファイル作成: terraform/environments/production.tfvars"
fi

# Lambda関連ファイル
create_if_not_exists "lambda/main.py"
create_if_not_exists "lambda/requirements.txt"

# フロントエンド関連ファイル
create_if_not_exists "frontend/public/index.html"
create_if_not_exists "frontend/src/App.js"
create_if_not_exists "frontend/src/App.css"
create_if_not_exists "frontend/package.json"

# Terraformデプロイスクリプトの作成
if [ ! -f "deploy_terraform.sh" ]; then
  cat > deploy_terraform.sh << 'EOF'
#!/bin/bash

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名]"
  echo "  環境名: development, staging, production など"
  echo "  例: $0 development"
  echo "      terraform/environments/development.tfvars を使用してデプロイ"
  echo "  環境名を指定しない場合は変数ファイルなしでデプロイします"
}

# 引数の処理
if [ $# -eq 1 ]; then
  if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 0
  fi
  
  ENV_NAME=$1
  VAR_FILE="terraform/environments/${ENV_NAME}.tfvars"
  
  if [ ! -f "$VAR_FILE" ]; then
    echo "エラー: 変数ファイル $VAR_FILE が見つかりません"
    echo "terraform/environments/ ディレクトリに ${ENV_NAME}.tfvars ファイルを作成するか、有効な環境名を指定してください"
    exit 1
  fi
  
  echo "${ENV_NAME} 環境の変数ファイルを使用してデプロイします: $VAR_FILE"
else
  echo "変数ファイルなしでデプロイします（デフォルト値が使用されます）"
  VAR_FILE=""
fi

# terraformディレクトリに移動
cd terraform

# Terraformの初期化
terraform init

# 変数ファイルの有無によってコマンドを変更
if [ -n "$VAR_FILE" ]; then
  # 相対パスを調整
  REL_VAR_FILE="../${VAR_FILE}"
  
  # プラン表示
  terraform plan -var-file="${REL_VAR_FILE}"
  
  # 確認プロンプト
  read -p "上記の計画を適用しますか？ (y/n): " CONFIRM
  if [ "$CONFIRM" == "y" ] || [ "$CONFIRM" == "Y" ]; then
    # デプロイ実行
    terraform apply -var-file="${REL_VAR_FILE}"
  else
    echo "デプロイをキャンセルしました"
    exit 0
  fi
else
  # プラン表示
  terraform plan
  
  # 確認プロンプト
  read -p "上記の計画を適用しますか？ (y/n): " CONFIRM
  if [ "$CONFIRM" == "y" ] || [ "$CONFIRM" == "Y" ]; then
    # デプロイ実行
    terraform apply
  else
    echo "デプロイをキャンセルしました"
    exit 0
  fi
fi

cd ..

echo "Terraformのデプロイが完了しました"
EOF
  chmod +x deploy_terraform.sh
  echo "ファイル作成: deploy_terraform.sh"
else
  echo "ファイル存在: deploy_terraform.sh (既存ファイルを保持します)"
fi

# Lambda関数デプロイスクリプトの作成
if [ ! -f "deploy_lambda.sh" ]; then
  cat > deploy_lambda.sh << 'EOF'
#!/bin/bash

# 一時ディレクトリを作成
mkdir -p build
cd build

# 必要なパッケージをインストール
pip install -r ../lambda/requirements.txt --target .

# メインコードをコピー
cp ../lambda/main.py .

# ZIPファイルを作成
zip -r ../lambda_function.zip .

# 元のディレクトリに戻る
cd ..

# lambda_function.zipを移動
cp lambda_function.zip terraform/

echo "Lambda関数のデプロイパッケージ lambda_function.zip が作成されました"
EOF
  echo "ファイル作成: deploy_lambda.sh"
else
  echo "ファイル存在: deploy_lambda.sh (既存ファイルを保持します)"
fi

# フロントエンドデプロイスクリプトの作成
if [ ! -f "deploy_frontend.sh" ]; then
  cat > deploy_frontend.sh << 'EOF'
#!/bin/bash

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名]"
  echo "  環境名: development, production など"
  echo "  例: $0 development"
  echo "      development環境のS3バケットにデプロイ"
  echo "  環境名を指定しない場合はデフォルト(production)環境にデプロイします"
}

# デフォルト環境
ENV_NAME="production"
S3_BUCKET="kindle-sale-checker-frontend"

# 引数の処理
if [ $# -eq 1 ]; then
  if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 0
  fi
  
  ENV_NAME=$1
  
  # 環境ごとのS3バケット名を設定
  case "$ENV_NAME" in
    "development")
      S3_BUCKET="kindle-sale-checker-dev-frontend"
      ;;
    "production")
      S3_BUCKET="kindle-sale-checker-frontend"
      ;;
    *)
      echo "エラー: 不明な環境名 '$ENV_NAME'"
      show_usage
      exit 1
      ;;
  esac
fi

echo "${ENV_NAME} 環境の S3 バケット ${S3_BUCKET} にデプロイします"

# フロントエンドディレクトリに移動
cd frontend

# Reactアプリをビルド
npm run build

# S3バケットに同期（--deleteオプションで不要なファイルを削除）
aws s3 sync build/ s3://$S3_BUCKET --delete

echo "フロントエンドが S3 バケット $S3_BUCKET にデプロイされました"
EOF
  echo "ファイル作成: deploy_frontend.sh"
else
  echo "ファイル存在: deploy_frontend.sh (既存ファイルを保持します)"
fi

# 全体のデプロイスクリプト
if [ ! -f "deploy_all.sh" ]; then
  cat > deploy_all.sh << 'EOF'
#!/bin/bash

# 使用方法の表示
function show_usage {
  echo "使用方法: $0 [環境名]"
  echo "  環境名: development, production など"
  echo "  例: $0 development"
  echo "      development環境用の設定でデプロイ"
  echo "  環境名を指定しない場合はデフォルト(production)環境にデプロイします"
}

# デフォルト環境
ENV_NAME="production"

# 引数の処理
if [ $# -eq 1 ]; then
  if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_usage
    exit 0
  fi
  ENV_NAME=$1
fi

echo "${ENV_NAME} 環境へのデプロイを開始します"

# Terraformデプロイ
./deploy_terraform.sh $ENV_NAME

# Lambda関数のデプロイ
./deploy_lambda.sh

# APIエンドポイントを取得
API_ENDPOINT=$(cd terraform && terraform output -raw api_endpoint)
echo "API Endpoint: $API_ENDPOINT"

# フロントエンドのAPI_URLを更新
if [ -f "frontend/src/App.js" ]; then
  sed -i "s|const API_URL = '.*'|const API_URL = '$API_ENDPOINT'|" frontend/src/App.js
  echo "フロントエンドのAPI_URLを更新しました"
fi

# フロントエンドのデプロイ
./deploy_frontend.sh $ENV_NAME

echo "${ENV_NAME} 環境へのデプロイが完了しました"
EOF
  chmod +x deploy_all.sh
  echo "ファイル作成: deploy_all.sh"
else
  echo "ファイル存在: deploy_all.sh (既存ファイルを保持します)"
fi

# .gitignoreファイル
if [ ! -f ".gitignore" ]; then
  cat > .gitignore << 'EOF'
# Node.js関連
node_modules/
npm-debug.log
yarn-debug.log
yarn-error.log
package-lock.json
yarn.lock

# ビルド関連
build/
dist/
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Lambda関連
lambda_function.zip
__pycache__/
*.py[cod]
*$py.class
.Python
env/
venv/
ENV/
.venv/
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
*.egg-info/
.installed.cfg
*.egg

# Terraformの状態ファイル
.terraform/
terraform/.terraform/
*.tfstate
*.tfstate.backup
*.tfplan
terraform.tfvars
terraform/*.tfstate
terraform/*.tfstate.backup
terraform/*.tfplan
terraform/.terraformrc
terraform/terraform.rc

# エディタ関連
.idea/
.vscode/
*.swp
*.swo
*~

# OS関連
.DS_Store
Thumbs.db
EOF
  echo "ファイル作成: .gitignore"
else
  echo "ファイル存在: .gitignore (既存ファイルを保持します)"
fi

# README.mdの作成
if [ ! -f "README.md" ]; then
  cat > README.md << 'EOF'
# Kindle Sale Checker

AWS (S3, Lambda, DynamoDB)を使用したKindleの本のセール情報チェックシステムです。

## 概要

このプロジェクトは、AWSのサーバーレスアーキテクチャを活用した、Kindleの本のセール情報をトラッキングするWebアプリケーションです。
ユーザーはAmazonの本のURLと説明を入力して登録でき、別プログラムから価格やセール情報などを更新することが可能です。

## プロジェクト構造

```
kindle_sale_checker/
├── terraform/          # Terraformファイル
│   ├── main.tf         # メインのTerraformファイル
│   ├── variables.tf    # 変数定義
│   ├── outputs.tf      # 出力定義
│   ├── environments/   # 環境別変数ファイル
│   │   ├── development.tfvars # 開発環境用変数
│   │   └── production.tfvars  # 本番環境用変数
│   └── modules/        # Terraformモジュール
│       ├── s3/         # S3モジュール
│       ├── dynamodb/   # DynamoDBモジュール
│       ├── iam/        # IAMモジュール
│       ├── lambda/     # Lambdaモジュール
│       └── api_gateway/ # API Gatewayモジュール
├── lambda/             # Lambda関数のソースコード
│   ├── main.py         # FastAPIアプリケーション
│   └── requirements.txt # Pythonの依存関係
├── frontend/           # Reactフロントエンド
│   ├── public/         # 静的ファイル
│   ├── src/            # ソースコード
│   └── package.json    # npm設定
├── deploy_terraform.sh # Terraformデプロイスクリプト
├── deploy_lambda.sh    # Lambda関数デプロイスクリプト
├── deploy_frontend.sh  # フロントエンドデプロイスクリプト
├── deploy_all.sh       # 全体デプロイスクリプト
└── .gitignore          # Gitの除外ファイル設定
```

## セットアップと使用方法

### 初期セットアップ

```bash
# 初期セットアップ
./init_project.sh
```

### デプロイ

環境ごとにデプロイするには以下のコマンドを使用します：

```bash
# 開発環境にデプロイ
./deploy_all.sh development

# 本番環境にデプロイ（デフォルト）
./deploy_all.sh
# または
./deploy_all.sh production
```

### 個別コンポーネントのデプロイ

各コンポーネントを個別にデプロイすることもできます：

```bash
# Terraformインフラのみデプロイ
./deploy_terraform.sh [環境名]

# Lambda関数のみデプロイ
./deploy_lambda.sh

# フロントエンドのみデプロイ
./deploy_frontend.sh [環境名]
```

## 環境変数ファイルのカスタマイズ

環境ごとの設定を変更するには、`terraform/environments/`ディレクトリ内の`.tfvars`ファイルを編集します。
新しい環境を追加する場合は、既存のファイルをコピーして新しい環境名で保存し、必要に応じて`deploy_frontend.sh`スクリプトにもその環境のS3バケット名を追加してください。

## 開発ガイドライン

詳細な開発ガイドラインは更新中です...
EOF
  echo "ファイル作成: README.md"
else
  echo "ファイル存在: README.md (既存ファイルを保持します)"
fi

# スクリプトに実行権限を付与
chmod +x deploy_lambda.sh
chmod +x deploy_frontend.sh
if [ -f "deploy_terraform.sh" ]; then
  chmod +x deploy_terraform.sh
fi
if [ -f "deploy_all.sh" ]; then
  chmod +x deploy_all.sh
fi

# Gitリポジトリがまだ初期化されていなければ初期化
if [ ! -d ".git" ]; then
  git init
  echo "Gitリポジトリを初期化しました"
else
  echo "Gitリポジトリは既に初期化されています"
fi

# 変更がある場合のみコミット
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  git add .
  git commit -m "初期コミット: Kindle Sale Checkerのプロジェクト構造を整理"
  echo "変更をコミットしました"
else
  echo "コミットする変更はありません"
fi

echo "Kindle Sale Checker のプロジェクト構造とファイルの初期化が完了しました。"
echo "Terraformファイルは 'terraform/' ディレクトリにまとめられました。"
echo "環境ごとの変数ファイルは 'terraform/environments/' ディレクトリに保存されています。"