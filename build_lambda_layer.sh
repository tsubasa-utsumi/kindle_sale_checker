#!/bin/bash

echo "📦 共通Lambda Layerを作成中..."

# 作業ディレクトリの作成
LAYER_DIR=$(mktemp -d)
echo "🔧 作業ディレクトリ: $LAYER_DIR"

# クリーンアップ関数
cleanup() {
  echo "🧹 クリーンアップを実行中..."
  rm -rf "$LAYER_DIR"
}

# 終了時にクリーンアップを実行
trap cleanup EXIT

# Python パッケージ用のディレクトリ構造を作成
mkdir -p "$LAYER_DIR/python/lib/python3.13/site-packages"

# requirements.txtをレイヤーディレクトリにコピー
if [ ! -f "lambda/common_requirements.txt" ]; then
  echo "❌ エラー: lambda/common_requirements.txt が見つかりません"
  exit 1
fi

cp lambda/common_requirements.txt "$LAYER_DIR/"

echo "📦 必要なパッケージをインストール中..."
echo "  - boto3 (AWS SDK)"
echo "  - beautifulsoup4 (HTMLパーサー)"
echo "  - requests (HTTP通信)"
echo "  - line-bot-sdk (LINE通知)"

# 必要なパッケージをインストール
cd "$LAYER_DIR"
pip install -r common_requirements.txt --target python/lib/python3.13/site-packages

# インストール結果の確認
echo ""
echo "📋 インストールされたパッケージ:"
ls -la python/lib/python3.13/site-packages/ | head -20

# ZIPファイルを作成
echo ""
echo "🗜️ Lambda Layer ZIPファイルを作成中..."
zip -r lambda_common_layer.zip python

# ファイルサイズの確認
FILE_SIZE=$(du -h lambda_common_layer.zip | cut -f1)
echo "📊 Lambda Layer ZIPファイルサイズ: $FILE_SIZE"

# レイヤーZIPをプロジェクトディレクトリに移動
cd -
cp "$LAYER_DIR/lambda_common_layer.zip" terraform/

echo ""
echo "✅ 共通Lambda Layerパッケージが正常に作成されました"
echo ""
echo "📋 作成されたファイル:"
echo "  📁 terraform/lambda_common_layer.zip (サイズ: $FILE_SIZE)"
echo ""
echo "🔧 Lambda Layer設定:"
echo "  📝 レイヤー名: {project_name}_common_dependencies"
echo "  🐍 対応ランタイム: python3.13"
echo "  📦 含まれるパッケージ:"
echo "    - boto3: AWS SDK for Python"
echo "    - beautifulsoup4: HTMLパーサー"
echo "    - requests: HTTP通信ライブラリ"
echo "    - line-bot-sdk: LINE Messaging API SDK"
echo ""
echo "💡 用途:"
echo "  - kindle_items.py と kindle_scraper.py で共有"
echo "  - 依存関係の一元管理"
echo "  - Lambda関数のデプロイサイズ削減"