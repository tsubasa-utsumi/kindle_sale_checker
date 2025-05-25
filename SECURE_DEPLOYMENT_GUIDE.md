# 🔒 セキュアデプロイメントガイド

このガイドでは、機密情報がGitにコミットされることを防ぐためのセットアップと使用方法を説明します。

## 🚀 クイックスタート

### 1. セキュアデプロイメント環境のセットアップ

```bash
# セキュア環境をセットアップ
chmod +x setup_secure_deployment.sh
./setup_secure_deployment.sh
```

### 2. 通常のデプロイ実行

```bash
# 通常通りデプロイ（設定は自動生成されます）
./deploy_all.sh production --auto-yes
```

これで完了です！機密情報は自動的に環境変数ファイルに分離され、Gitにコミットされません。

## 📋 詳細説明

### 環境変数システム

このシステムでは以下のような構成になります：

#### ソースコード（Git管理対象）
- `frontend/src/App.js` - プレースホルダーを使用
- `frontend/src/authService.js` - プレースホルダーを使用
- `frontend/.env.example` - 設定のテンプレート

#### 環境設定ファイル（Git管理対象外）
- `frontend/.env.production` - 本番環境の実際の設定値
- `frontend/.env.development` - 開発環境の実際の設定値
- `terraform/terraform.tfvars` - Terraform用の機密情報

### プレースホルダー例

**App.js:**
```javascript
const getApiUrl = () => {
  return process.env.REACT_APP_API_ENDPOINT || 'TERRAFORM_API_ENDPOINT_PLACEHOLDER';
};
```

**authService.js:**
```javascript
const getUserPoolId = () => {
  return process.env.REACT_APP_COGNITO_USER_POOL_ID || 'TERRAFORM_USER_POOL_ID_PLACEHOLDER';
};
```

### 環境変数ファイル例

**frontend/.env.production:**
```bash
REACT_APP_API_ENDPOINT=https://d1abc2def3.cloudfront.net/api
REACT_APP_COGNITO_USER_POOL_ID=ap-northeast-1_ABC123DEF
REACT_APP_COGNITO_CLIENT_ID=1a2b3c4d5e6f7g8h9i0j
REACT_APP_AWS_REGION=ap-northeast-1
```

## 🛡️ セキュリティ機能

### 1. 自動的な機密情報の除外

**更新された.gitignore:**
```gitignore
# 環境変数ファイル（機密情報を含むため除外）
frontend/.env
frontend/.env.local
frontend/.env.production
frontend/.env.development
frontend/.env.production.local
frontend/.env.development.local

# Terraformの機密情報
terraform.tfvars
terraform/*.tfvars
```

### 2. 動的設定生成

`create_config_files.sh` が以下を自動実行：
1. Terraformから最新の設定値を取得
2. 環境変数ファイルを生成
3. テンプレートファイルを更新

### 3. デプロイ時の自動処理

`deploy_frontend.sh` が以下を自動実行：
1. 設定ファイルの生成
2. 環境変数の適用
3. ビルドとデプロイ
4. 一時ファイルのクリーンアップ

## 🔧 利用可能なコマンド

### セットアップ
```bash
# 初回セットアップ（1回のみ実行）
./setup_secure_deployment.sh
```

### デプロイ
```bash
# 全体デプロイ（推奨）
./deploy_all.sh production --auto-yes

# フロントエンドのみデプロイ
./deploy_frontend.sh production --auto-yes
```

### メンテナンス
```bash
# 設定ファイルを手動生成
./create_config_files.sh

# ソースコードをプレースホルダーに戻す
./reset_to_placeholders.sh
```

## 🚨 トラブルシューティング

### 設定エラーが表示される場合

```bash
# 1. Terraformが正しくデプロイされているか確認
cd terraform
terraform output

# 2. 設定ファイルを再生成
cd ..
./create_config_files.sh

# 3. フロントエンドを再デプロイ
./deploy_frontend.sh production --auto-yes
```

### 機密情報がソースコードに含まれている場合

```bash
# プレースホルダーに戻す
./reset_to_placeholders.sh

# Gitコミット前に確認
git diff
```

### 環境変数ファイルが見つからない場合

```bash
# 設定ファイルを生成
./create_config_files.sh

# ファイルの存在確認
ls -la frontend/.env*
```

## 📝 開発者向けの注意事項

### Gitコミット前のチェック

```bash
# 機密情報が含まれていないか確認
git diff --cached | grep -E "(REACT_APP_.*=|UserPoolId:|ClientId:)" && echo "⚠️ 機密情報が含まれています！" || echo "✅ 安全です"
```

### 新しい環境変数の追加

1. `create_config_files.sh` を更新
2. `frontend/src/App.js` または `authService.js` にプレースホルダーを追加
3. `frontend/.env.example` にサンプル値を追加

### デバッグモード

開発時は以下の環境変数を設定：

```bash
# frontend/.env.development
REACT_APP_DEBUG_MODE=true
```

これにより、ブラウザのコンソールに詳細なログが表示されます。

## 🎯 ベストプラクティス

### 1. 定期的なセキュリティチェック

```bash
# 機密情報の漏洩チェック
git log --oneline -10 | xargs -I {} git show {} | grep -E "pool.*ap-northeast|client.*[a-z0-9]{26}" && echo "⚠️ 過去のコミットに機密情報が含まれています"
```

### 2. チーム開発での運用

- **初回セットアップ**: 各開発者が `setup_secure_deployment.sh` を実行
- **環境共有**: `.env.example` ファイルで設定項目を共有
- **個別設定**: 各開発者が独自の `.env.development` を作成

### 3. CI/CDでの運用

```yaml
# GitHub Actions例
- name: Setup secure deployment
  run: |
    ./setup_secure_deployment.sh
    # 環境変数をシークレットから設定
    echo "REACT_APP_API_ENDPOINT=${{ secrets.API_ENDPOINT }}" >> frontend/.env.production
```

## 🔄 既存プロジェクトからの移行

既存のプロジェクトでこのシステムを導入する場合：

```bash
# 1. 現在の設定をバックアップ
cp frontend/src/App.js frontend/src/App.js.backup
cp frontend/src/authService.js frontend/src/authService.js.backup

# 2. セキュアシステムを導入
./setup_secure_deployment.sh

# 3. 設定の動作確認
./deploy_frontend.sh production

# 4. Gitコミット（機密情報が除外されることを確認）
git add .
git commit -m "feat: セキュアデプロイメントシステムを導入"
```

このシステムにより、機密情報の漏洩リスクを大幅に削減し、安全な継続的デプロイメントが可能になります。