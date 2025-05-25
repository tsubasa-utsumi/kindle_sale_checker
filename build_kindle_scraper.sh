#!/bin/bash

echo "🕷️ Kindle Scraper Lambda関数のデプロイパッケージを作成中..."

# プロジェクトのルートディレクトリを確認
if [ ! -f "lambda/kindle_scraper.py" ]; then
  echo "❌ エラー: lambda/kindle_scraper.py が見つかりません。"
  exit 1
fi

# ビルドディレクトリを作成/クリア
rm -rf build_scraper
mkdir -p build_scraper

echo "📁 Lambda関数のコードのみをコピー（依存ライブラリはレイヤーに移行済み）"
cp lambda/kindle_scraper.py build_scraper/

# シンプルなZIPファイル作成（依存ライブラリなし）
cd build_scraper
zip -r lambda_scraper_function.zip kindle_scraper.py

# ZIPファイルの内容を確認
echo ""
echo "📋 ZIPファイルの内容:"
unzip -l lambda_scraper_function.zip

# ZIPファイルのサイズを確認
FILE_SIZE=$(du -h lambda_scraper_function.zip | cut -f1)
echo ""
echo "📊 ZIPファイルのサイズ: $FILE_SIZE"

# 元のディレクトリに戻る
cd ..

# ZIPファイルをterraformディレクトリにコピー
cp build_scraper/lambda_scraper_function.zip terraform/

echo ""
echo "✅ Kindle Scraper Lambda関数のデプロイパッケージが正常に作成されました"
echo ""
echo "📋 作成されたファイル:"
echo "  📁 terraform/lambda_scraper_function.zip (サイズ: $FILE_SIZE)"
echo ""
echo "🔧 Lambda関数設定:"
echo "  📝 Handler: kindle_scraper.handler"
echo "  🚀 メイン関数: lambda_handler"
echo "  🔄 互換関数: handler"
echo "  📦 依存関係: Lambda Layerとして別途デプロイ"
echo "  ⏱️ タイムアウト: 600秒（10分）"
echo "  💾 メモリ: 256MB"
echo ""
echo "💡 役割:"
echo "  - Amazonからの価格スクレイピング"
echo "  - セール情報の検出と通知"
echo "  - 自動スケジューリング機能"
echo "  - LINE Messaging API連携"