#!/bin/bash

echo "Kindle Sale Checker用のLambdaレイヤーを作成しています..."

# 作業ディレクトリの作成
LAYER_DIR=$(mktemp -d)
echo "作業ディレクトリ: $LAYER_DIR"

# クリーンアップ関数
cleanup() {
  echo "クリーンアップを実行中..."
  rm -rf "$LAYER_DIR"
}

# 終了時にクリーンアップを実行
trap cleanup EXIT

# Python パッケージ用のディレクトリ構造を作成
mkdir -p "$LAYER_DIR/python/lib/python3.13/site-packages"  # Python 3.13に更新

# requirements.txtをレイヤーディレクトリにコピー
cp lambda/common_requirements.txt "$LAYER_DIR/"

# 必要なパッケージをインストール
cd "$LAYER_DIR"
pip install -r common_requirements.txt --target python/lib/python3.13/site-packages  # Python 3.13に更新

# ZIPファイルを作成
zip -r lambda_common_layer.zip python

# レイヤーZIPをプロジェクトディレクトリに移動
cd -
cp "$LAYER_DIR/lambda_common_layer.zip" terraform/

echo "Lambda レイヤーパッケージ terraform/lambda_common_layer.zip が作成されました"