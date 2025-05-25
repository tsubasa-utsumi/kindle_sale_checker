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