#!/bin/bash

echo "📦 Kindle Items API Lambda関数のデプロイパッケージを作成中..."

# プロジェクトのルートディレクトリを確認
if [ ! -d "lambda" ]; then
  echo "❌ エラー: lambdaディレクトリが見つかりません。プロジェクトのルートディレクトリで実行してください。"
  exit 1
fi

# kindle_items.pyの存在確認
if [ ! -f "lambda/kindle_items.py" ]; then
  echo "❌ エラー: lambda/kindle_items.py が見つかりません。"
  echo "main.py から kindle_items.py への名前変更が完了していることを確認してください。"
  exit 1
fi

# ビルドディレクトリを作成/クリア
rm -rf build
mkdir -p build

echo "📁 Lambda関数のコードのみをコピー（依存関係はレイヤーに移行済み）"
cp lambda/kindle_items.py build/

# ZIPファイル作成
cd build
zip -r lambda_function.zip kindle_items.py

# ZIPファイルの内容を確認
echo ""
echo "📋 ZIPファイルの内容:"
unzip -l lambda_function.zip

# ZIPファイルのサイズ確認
FILE_SIZE=$(du -h lambda_function.zip | cut -f1)
echo ""
echo "📊 ZIPファイルのサイズ: $FILE_SIZE"

# 元のディレクトリに戻る
cd ..

# ZIPファイルをTerraformディレクトリにコピー
cp build/lambda_function.zip terraform/

echo ""
echo "✅ Kindle Items API Lambda関数のデプロイパッケージが正常に作成されました"
echo ""
echo "📋 作成されたファイル:"
echo "  📁 terraform/lambda_function.zip (サイズ: $FILE_SIZE)"
echo ""
echo "🔧 Lambda関数設定:"
echo "  📝 Handler: kindle_items.handler"
echo "  🚀 メイン関数: lambda_handler"
echo "  🔄 互換関数: handler"
echo "  📦 依存関係: Lambda Layerとして別途デプロイ"
echo ""
echo "💡 役割:"
echo "  - Kindleアイテムの登録・取得・削除"
echo "  - API Gateway経由でのCRUD操作"
echo "  - Cognito認証による保護"