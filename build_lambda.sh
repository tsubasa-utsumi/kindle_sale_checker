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