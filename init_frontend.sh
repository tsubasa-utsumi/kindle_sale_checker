#!/bin/bash

echo "フロントエンドプロジェクトを初期化しています..."

# フロントエンドディレクトリに移動
cd frontend || exit 1

# package.jsonがない場合は新規作成
if [ ! -f "package.json" ]; then
  echo "package.jsonを作成しています..."
  cat > package.json << 'EOF'
{
  "name": "kindle-sale-checker-frontend",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "@testing-library/jest-dom": "^5.16.5",
    "@testing-library/react": "^13.4.0",
    "@testing-library/user-event": "^13.5.0",
    "axios": "^1.4.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "web-vitals": "^2.1.4"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  }
}
EOF
  echo "package.json を作成しました"
fi

# publicディレクトリの確認と初期化
if [ ! -d "public" ]; then
  mkdir -p public
fi

# index.htmlが存在しない場合は作成
if [ ! -f "public/index.html" ]; then
  echo "public/index.html を作成しています..."
  cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8" />
    <link rel="icon" href="%PUBLIC_URL%/favicon.ico" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta name="description" content="Kindle本のセール情報をチェックするWebアプリ" />
    <link rel="apple-touch-icon" href="%PUBLIC_URL%/logo192.png" />
    <link rel="manifest" href="%PUBLIC_URL%/manifest.json" />
    <title>Kindle Sale Checker</title>
  </head>
  <body>
    <noscript>このアプリを実行するにはJavaScriptを有効にする必要があります。</noscript>
    <div id="root"></div>
  </body>
</html>
EOF
  echo "public/index.html を作成しました"
fi

# manifest.jsonを作成
if [ ! -f "public/manifest.json" ]; then
  echo "public/manifest.json を作成しています..."
  cat > public/manifest.json << 'EOF'
{
  "short_name": "Kindle Checker",
  "name": "Kindle Sale Checker",
  "icons": [
    {
      "src": "favicon.ico",
      "sizes": "64x64 32x32 24x24 16x16",
      "type": "image/x-icon"
    }
  ],
  "start_url": ".",
  "display": "standalone",
  "theme_color": "#000000",
  "background_color": "#ffffff"
}
EOF
  echo "public/manifest.json を作成しました"
fi

# robotsを作成
if [ ! -f "public/robots.txt" ]; then
  echo "public/robots.txt を作成しています..."
  cat > public/robots.txt << 'EOF'
# https://www.robotstxt.org/robotstxt.html
User-agent: *
Disallow:
EOF
  echo "public/robots.txt を作成しました"
fi

# srcディレクトリの確認と初期化
if [ ! -d "src" ]; then
  mkdir -p src
fi

# App.jsが存在しない場合は作成
if [ ! -f "src/App.js" ]; then
  echo "src/App.js を作成しています..."
  cat > src/App.js << 'EOF'
import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';

// APIのベースURL - デプロイ後に適切なURLに変更する
const API_URL = 'https://your-api-gateway-url.execute-api.ap-northeast-1.amazonaws.com';

function App() {
  const [items, setItems] = useState([]);
  const [url, setUrl] = useState('');
  const [description, setDescription] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  // アイテム一覧を取得
  const fetchItems = async () => {
    setLoading(true);
    try {
      const response = await axios.get(`${API_URL}/items/`);
      setItems(response.data);
      setError(null);
    } catch (err) {
      console.error('アイテムの取得に失敗しました:', err);
      setError('アイテムの取得に失敗しました。');
    } finally {
      setLoading(false);
    }
  };

  // コンポーネントのマウント時にアイテム一覧を取得
  useEffect(() => {
    fetchItems();
  }, []);

  // アイテムを追加
  const addItem = async (e) => {
    e.preventDefault();
    
    if (!url || !description) {
      setError('URLと説明を入力してください。');
      return;
    }

    setLoading(true);
    try {
      await axios.post(`${API_URL}/items/`, {
        url,
        description,
      });
      
      // フォームをリセット
      setUrl('');
      setDescription('');
      
      // アイテム一覧を再取得
      fetchItems();
      setError(null);
    } catch (err) {
      console.error('アイテムの追加に失敗しました:', err);
      setError('アイテムの追加に失敗しました。');
    } finally {
      setLoading(false);
    }
  };

  // アイテムを削除
  const deleteItem = async (id) => {
    if (window.confirm('このアイテムを削除してもよろしいですか？')) {
      setLoading(true);
      try {
        await axios.delete(`${API_URL}/items/${id}`);
        // アイテム一覧を再取得
        fetchItems();
        setError(null);
      } catch (err) {
        console.error('アイテムの削除に失敗しました:', err);
        setError('アイテムの削除に失敗しました。');
      } finally {
        setLoading(false);
      }
    }
  };

  return (
    <div className="app-container">
      <h1>Kindle Sale Checker</h1>
      
      {/* エラーメッセージ */}
      {error && <div className="error-message">{error}</div>}
      
      {/* アイテム追加フォーム */}
      <div className="form-container">
        <h2>Kindleの本を追加</h2>
        <form onSubmit={addItem}>
          <div className="form-group">
            <label htmlFor="url">URL:</label>
            <input
              type="url"
              id="url"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder="https://amazon.co.jp/dp/..."
              required
            />
          </div>
          
          <div className="form-group">
            <label htmlFor="description">本のタイトル:</label>
            <textarea
              id="description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="本のタイトルと著者名"
              required
            />
          </div>
          
          <button type="submit" disabled={loading}>
            {loading ? '処理中...' : '追加'}
          </button>
        </form>
      </div>
      
      {/* アイテム一覧 */}
      <div className="items-container">
        <h2>登録済みの本</h2>
        {loading && <p>読み込み中...</p>}
        
        {items.length === 0 && !loading ? (
          <p>登録されている本はありません。</p>
        ) : (
          <ul className="items-list">
            {items.map((item) => (
              <li key={item.id} className="item-card">
                <div className="item-header">
                  <h3>{item.description}</h3>
                  <button
                    className="delete-button"
                    onClick={() => deleteItem(item.id)}
                    disabled={loading}
                  >
                    削除
                  </button>
                </div>
                
                <div className="item-details">
                  <p>
                    <strong>URL:</strong>{' '}
                    <a href={item.url} target="_blank" rel="noopener noreferrer">
                      {item.url}
                    </a>
                  </p>
                  
                  {item.has_sale !== null && (
                    <p>
                      <strong>セール中:</strong> {item.has_sale ? 'はい' : 'いいえ'}
                    </p>
                  )}
                  
                  {item.current_price !== null && (
                    <p>
                      <strong>現在価格:</strong> ¥{item.current_price.toLocaleString()}
                    </p>
                  )}
                  
                  {item.points !== null && (
                    <p>
                      <strong>ポイント:</strong> {item.points.toLocaleString()}ポイント
                    </p>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

export default App;
EOF
  echo "src/App.js を作成しました"
fi

# App.cssが存在しない場合は作成
if [ ! -f "src/App.css" ]; then
  echo "src/App.css を作成しています..."
  cat > src/App.css << 'EOF'
/* App.css */
* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  font-family: 'Hiragino Sans', 'Meiryo', sans-serif;
  line-height: 1.6;
  color: #333;
  background-color: #f5f5f5;
  padding: 20px;
}

.app-container {
  max-width: 1000px;
  margin: 0 auto;
  padding: 20px;
  background-color: #fff;
  border-radius: 8px;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
}

h1 {
  text-align: center;
  margin-bottom: 30px;
  color: #3498db;
}

h2 {
  margin-bottom: 20px;
  border-bottom: 2px solid #eee;
  padding-bottom: 10px;
  color: #2c3e50;
}

.error-message {
  background-color: #ffecec;
  color: #f44336;
  padding: 10px;
  border-radius: 4px;
  margin-bottom: 20px;
  border-left: 4px solid #f44336;
}

.form-container {
  margin-bottom: 40px;
}

.form-group {
  margin-bottom: 15px;
}

label {
  display: block;
  margin-bottom: 5px;
  font-weight: bold;
}

input[type="url"],
textarea {
  width: 100%;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 16px;
}

textarea {
  height: 100px;
  resize: vertical;
}

button {
  background-color: #3498db;
  color: white;
  border: none;
  padding: 10px 20px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 16px;
  transition: background-color 0.3s;
}

button:hover {
  background-color: #2980b9;
}

button:disabled {
  background-color: #bdc3c7;
  cursor: not-allowed;
}

.items-list {
  list-style: none;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 20px;
}

.item-card {
  border: 1px solid #eee;
  border-radius: 8px;
  padding: 15px;
  box-shadow: 0 2px 5px rgba(0, 0, 0, 0.05);
  background-color: #fff;
  transition: transform 0.2s, box-shadow 0.2s;
}

.item-card:hover {
  transform: translateY(-5px);
  box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
}

.item-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 10px;
}

.item-header h3 {
  margin: 0;
  word-break: break-word;
}

.delete-button {
  background-color: #e74c3c;
  padding: 5px 10px;
  font-size: 14px;
}

.delete-button:hover {
  background-color: #c0392b;
}

.item-details {
  font-size: 14px;
}

.item-details p {
  margin-bottom: 8px;
}

.item-details a {
  color: #3498db;
  text-decoration: none;
  word-break: break-all;
}

.item-details a:hover {
  text-decoration: underline;
}

@media (max-width: 768px) {
  .items-list {
    grid-template-columns: 1fr;
  }
  
  .app-container {
    padding: 15px;
  }
}
EOF
  echo "src/App.css を作成しました"
fi

# index.jsが存在しない場合は作成
if [ ! -f "src/index.js" ]; then
  echo "src/index.js を作成しています..."
  cat > src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';
import reportWebVitals from './reportWebVitals';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

// If you want to start measuring performance in your app, pass a function
// to log results (for example: reportWebVitals(console.log))
// or send to an analytics endpoint. Learn more: https://bit.ly/CRA-vitals
reportWebVitals();
EOF
  echo "src/index.js を作成しました"
fi

# index.cssが存在しない場合は作成
if [ ! -f "src/index.css" ]; then
  echo "src/index.css を作成しています..."
  cat > src/index.css << 'EOF'
body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
    sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

code {
  font-family: source-code-pro, Menlo, Monaco, Consolas, 'Courier New',
    monospace;
}
EOF
  echo "src/index.css を作成しました"
fi

# reportWebVitalsが存在しない場合は作成
if [ ! -f "src/reportWebVitals.js" ]; then
  echo "src/reportWebVitals.js を作成しています..."
  cat > src/reportWebVitals.js << 'EOF'
const reportWebVitals = onPerfEntry => {
  if (onPerfEntry && onPerfEntry instanceof Function) {
    import('web-vitals').then(({ getCLS, getFID, getFCP, getLCP, getTTFB }) => {
      getCLS(onPerfEntry);
      getFID(onPerfEntry);
      getFCP(onPerfEntry);
      getLCP(onPerfEntry);
      getTTFB(onPerfEntry);
    });
  }
};

export default reportWebVitals;
EOF
  echo "src/reportWebVitals.js を作成しました"
fi

# 依存関係をインストール
echo "Reactアプリの依存関係をインストールしています..."

# package.jsonから依存関係を抽出してインストール (必要なモジュールを確実にインストール)
if [ -f "package.json" ]; then
  # 明示的に必要なパッケージをインストール（この部分を追加）
  npm install react react-dom react-scripts axios web-vitals @testing-library/jest-dom @testing-library/react @testing-library/user-event --save

  # package.jsonにあるその他の依存関係もインストール
  npm install
else
  echo "package.jsonが見つかりません"
  exit 1
fi

echo "依存関係のインストールが完了しました"

echo "フロントエンドプロジェクトの初期化が完了しました。"
echo "以下のコマンドでローカルサーバーを起動できます:"
echo "  cd frontend && npm start"
echo ""
echo "ビルドするには以下のコマンドを実行します:"
echo "  cd frontend && npm run build"