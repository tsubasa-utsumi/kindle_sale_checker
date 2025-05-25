// frontend/src/App.js (CloudFront API統合版)
import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';
import AuthComponent from './AuthComponent';
import { getCurrentUser, signOut, getIdToken } from './authService';

// APIのベースURL - デプロイ時にTerraformのoutputから自動設定
const API_URL = 'TERRAFORM_API_ENDPOINT_PLACEHOLDER';

function App() {
  const [items, setItems] = useState([]);
  const [url, setUrl] = useState('');
  const [loading, setLoading] = useState(false);
  const [updating, setUpdating] = useState(false);
  const [error, setError] = useState(null);
  const [latestUpdate, setLatestUpdate] = useState(null);
  const [user, setUser] = useState(null);
  const [authLoading, setAuthLoading] = useState(true);

  // 認証状態チェック
  useEffect(() => {
    checkAuthState();
  }, []);

  const checkAuthState = async () => {
    try {
      const currentUser = await getCurrentUser();
      setUser(currentUser);
      if (currentUser) {
        // 認証済みの場合、アイテム一覧を取得
        fetchItems();
      }
    } catch (error) {
      console.log('認証されていません:', error);
      setUser(null);
    } finally {
      setAuthLoading(false);
    }
  };

  // 認証付きHTTPクライアントの設定
  const getAuthenticatedAxios = async () => {
    try {
      const token = await getIdToken();
      return axios.create({
        baseURL: API_URL,
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        timeout: 30000
      });
    } catch (error) {
      console.error('トークン取得エラー:', error);
      throw new Error('認証トークンの取得に失敗しました');
    }
  };

  // 日時のフォーマット関数（UTC → JST変換付き）
  const formatDateTime = (isoString) => {
    if (!isoString) return '未更新';
    
    const date = new Date(isoString);
    const jstDate = new Date(date.getTime() + 9 * 60 * 60 * 1000);
    
    return `${jstDate.getFullYear()}/${(jstDate.getMonth() + 1).toString().padStart(2, '0')}/${jstDate.getDate().toString().padStart(2, '0')} ${jstDate.getHours().toString().padStart(2, '0')}:${jstDate.getMinutes().toString().padStart(2, '0')}`;
  };

  // 更新状態をチェックする関数
  const checkUpdateStatus = (items) => {
    const updateLock = items.find(item => item.id === '__UPDATE_LOCK__');
    if (updateLock && updateLock.status === 'running') {
      try {
        const startTime = new Date(updateLock.started_at);
        const now = new Date();
        
        if (isNaN(startTime.getTime())) {
          console.warn('無効な開始時刻:', updateLock.started_at);
          return { isUpdating: false };
        }
        
        const elapsedMilliseconds = now.getTime() - startTime.getTime();
        const elapsedMinutes = elapsedMilliseconds / (1000 * 60);
        
        console.log('更新状態チェック:', {
          startTime: updateLock.started_at,
          now: now.toISOString(),
          elapsedMinutes: Math.round(elapsedMinutes * 10) / 10,
          isWithinHour: elapsedMinutes < 60
        });
        
        if (elapsedMinutes < 60 && elapsedMinutes >= 0) {
          return { 
            isUpdating: true, 
            elapsed: elapsedMinutes,
            startTime: updateLock.started_at 
          };
        } else {
          console.log('更新ロックが期限切れです:', Math.round(elapsedMinutes), '分経過');
        }
      } catch (error) {
        console.error('時刻の解析エラー:', error, updateLock.started_at);
      }
    }
    return { isUpdating: false };
  };

  // リトライ機能付きのAPIコール
  const apiCallWithRetry = async (apiCall, maxRetries = 3, retryDelay = 2000) => {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        const result = await apiCall();
        return result;
      } catch (error) {
        console.log(`API呼び出し試行 ${attempt}/${maxRetries} でエラー:`, error.message);
        
        // 認証エラーの場合は即座に失敗
        if (error.response?.status === 401 || error.response?.status === 403) {
          console.error('認証エラー:', error.response?.data);
          await signOut();
          setUser(null);
          throw new Error('認証に失敗しました。再度ログインしてください。');
        }
        
        // 503エラーまたはネットワークエラーの場合はリトライ
        if (attempt < maxRetries && (
          error.response?.status === 503 || 
          error.response?.status === 502 ||
          error.response?.status === 504 ||
          error.code === 'ECONNABORTED' ||
          error.message.includes('Network Error')
        )) {
          console.log(`${retryDelay}ms後にリトライします...`);
          await new Promise(resolve => setTimeout(resolve, retryDelay));
          retryDelay *= 1.5;
        } else {
          throw error;
        }
      }
    }
  };

  // アイテム一覧を取得（認証付き）
  const fetchItems = async (skipLoadingState = false) => {
    if (!skipLoadingState) {
      setLoading(true);
    }
    
    try {
      const authAxios = await getAuthenticatedAxios();
      const response = await apiCallWithRetry(
        () => authAxios.get('/items/')
      );
      
      console.log('API Response:', response.data);
      
      if (Array.isArray(response.data)) {
        const updateStatus = checkUpdateStatus(response.data);
        
        if (updateStatus.isUpdating && !updating) {
          setUpdating(true);
          console.log('更新中状態を検出:', updateStatus);
        } else if (!updateStatus.isUpdating && updating) {
          setUpdating(false);
          console.log('更新完了を検出');
        }
        
        const bookItems = response.data.filter(item => item.id !== '__UPDATE_LOCK__');
        
        const sortedItems = [...bookItems].sort((a, b) => {
          if (a.has_sale && !b.has_sale) return -1;
          if (!a.has_sale && b.has_sale) return 1;
          
          const ratioA = a.current_price && a.points ? (a.points / a.current_price) * 100 : 0;
          const ratioB = b.current_price && b.points ? (b.points / b.current_price) * 100 : 0;
          
          if (ratioA > ratioB) return -1;
          if (ratioA < ratioB) return 1;
          
          if (a.updated_at && b.updated_at) {
            return new Date(b.updated_at) - new Date(a.updated_at);
          }
          
          return 0;
        });
        setItems(sortedItems);
        
        let latest = null;
        bookItems.forEach(item => {
          if (item.updated_at) {
            const updateTime = new Date(item.updated_at);
            if (!latest || updateTime > new Date(latest)) {
              latest = item.updated_at;
            }
          }
        });
        setLatestUpdate(latest);
        
        return updateStatus;
      } else {
        console.error('Expected an array but got:', typeof response.data);
        setItems([]);
        setError('データ形式が不正です。管理者に連絡してください。');
        return { isUpdating: false };
      }
      
    } catch (err) {
      console.error('アイテムの取得に失敗しました:', err);
      setError('アイテムの取得に失敗しました。');
      setItems([]);
      return { isUpdating: false };
    } finally {
      if (!skipLoadingState) {
        setLoading(false);
      }
    }
  };

  // 更新中の場合は定期的にポーリング
  useEffect(() => {
    let interval;
    
    if (updating && user) {
      console.log('更新中のポーリングを開始します（1分間隔）');
      interval = setInterval(async () => {
        try {
          const updateStatus = await fetchItems(true);
          
          if (updateStatus && !updateStatus.isUpdating) {
            console.log('ポーリングで更新完了を検出しました');
            setUpdating(false);
          } else if (updateStatus && updateStatus.isUpdating) {
            console.log('まだ更新中です。経過時間:', Math.round(updateStatus.elapsed * 10) / 10, '分');
          }
        } catch (error) {
          console.error('ポーリング中にエラーが発生:', error);
        }
      }, 60000);
    }
    
    return () => {
      if (interval) {
        console.log('ポーリングを停止します');
        clearInterval(interval);
      }
    };
  }, [updating, user]);

  // アイテムを追加（認証付き）
  const addItem = async (e) => {
    e.preventDefault();
    
    if (!url) {
      setError('URLを入力してください。');
      return;
    }

    setLoading(true);
    try {
      const authAxios = await getAuthenticatedAxios();
      const response = await apiCallWithRetry(
        () => authAxios.post('/items', { url })
      );
      
      console.log('Item created:', response.data);
      
      setUrl('');
      fetchItems();
      setError(null);
    } catch (err) {
      console.error('アイテムの追加に失敗しました:', err);
      
      if (err.response?.status === 503) {
        setError('サーバーが一時的に利用できません。しばらく待ってから再度お試しください。');
      } else {
        setError(`アイテムの追加に失敗しました: ${err.response?.data?.detail || err.message}`);
      }
    } finally {
      setLoading(false);
    }
  };

  // アイテムを削除（認証付き）
  const deleteItem = async (id) => {
    if (window.confirm('このアイテムを削除してもよろしいですか？')) {
      setLoading(true);
      try {
        const authAxios = await getAuthenticatedAxios();
        await authAxios.delete(`/items/${id}`);
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

  // 更新（認証付き）
  const updateItems = async () => {
    if (updating) {
      console.log('既に更新処理が実行中です');
      return;
    }

    setUpdating(true);
    setError(null);
    
    try {
      console.log('スクレイパーの更新を開始します...');
      
      const authAxios = await getAuthenticatedAxios();
      authAxios.post('/update', {}, { 
        timeout: 5000
      }).then(response => {
        console.log('更新開始が正常に受け付けられました:', response.data);
      }).catch(err => {
        console.warn('更新開始の確認でエラーが発生しましたが、処理は継続している可能性があります:', err.message);
      });
      
      console.log('更新リクエストを送信しました。ポーリングで状態を監視します。');
      
    } catch (err) {
      console.error('更新の開始に失敗しました:', err);
      setUpdating(false);
      
      if (err.response?.status === 409) {
        setError('既に更新処理が実行中です。しばらく待ってから再度お試しください。');
      } else {
        setError(`更新の開始に失敗しました: ${err.response?.data?.detail || err.message}`);
      }
    }
  };

  // ログアウト処理
  const handleSignOut = async () => {
    try {
      await signOut();
      setUser(null);
      setItems([]);
      setError(null);
    } catch (error) {
      console.error('ログアウトエラー:', error);
    }
  };

  // 数値のフォーマット
  const formatNumber = (value) => {
    if (value === null || value === undefined) return '';
    return value.toLocaleString();
  };

  // ポイント率の計算
  const calculatePointRatio = (price, points) => {
    if (!price || !points || price === 0) return 0;
    return Math.round((points / price) * 100);
  };

  // 認証状態をチェック中
  if (authLoading) {
    return (
      <div className="app-container">
        <div className="loading-container">
          <h2>認証状態を確認中...</h2>
        </div>
      </div>
    );
  }

  // 未認証の場合はログイン画面を表示
  if (!user) {
    return <AuthComponent onAuthSuccess={checkAuthState} />;
  }

  // 認証済みの場合はメインアプリを表示
  return (
    <div className={`app-container ${updating ? 'updating' : ''}`}>
      <div className="header">
        <h1>Kindle Sale Checker</h1>
        <div className="user-info">
          <span>ログイン中: {user.email}</span>
          <button onClick={handleSignOut} className="sign-out-button">
            ログアウト
          </button>
        </div>
      </div>
      
      {/* エラーメッセージ */}
      {error && <div className="error-message">{error}</div>}
      
      {/* アイテム追加フォーム */}
      <div className={`form-container ${updating ? 'disabled' : ''}`}>
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
              disabled={updating}
            />
          </div>
          
          <button type="submit" disabled={loading || updating}>
            {loading ? '処理中...' : '追加'}
          </button>
        </form>
      </div>
      
      {/* アイテム一覧 */}
      <div className="items-container">
        <div className="items-header">
          <h2>登録済みの本</h2>
          <div className="update-info">
            <span>最終更新: {formatDateTime(latestUpdate)}</span>
            <button 
              className={`update-button ${updating ? 'updating' : ''}`}
              onClick={updateItems}
              disabled={loading || updating}
            >
              {updating ? '更新中...' : '更新'}
            </button>
          </div>
        </div>
        
        {/* 更新中のメッセージ */}
        {updating && (
          <div className="update-status">
            <p>📚 Kindle情報を更新中です。この処理には数分かかる場合があります...</p>
            <p>💡 ページを閉じても処理は継続されます。しばらくしてから再度確認してください。</p>
            <p>🔒 更新中は全ての操作が無効になります。</p>
          </div>
        )}
        
        {loading && !updating && <p>読み込み中...</p>}
        
        {!loading && !updating && Array.isArray(items) && items.length === 0 ? (
          <p>登録されている本はありません。</p>
        ) : (
          <ul className="items-list">
            {Array.isArray(items) && items.map((item) => (
              <li 
                key={item.id} 
                className={`item-card ${item.has_sale ? 'item-sale' : ''} ${updating ? 'disabled' : ''}`}
              >
                <div className="item-header">
                  <h3>
                    <a 
                      href={item.url} 
                      target="_blank" 
                      rel="noopener noreferrer" 
                      title={item.description || item.url}
                      style={{ 
                        pointerEvents: updating ? 'none' : 'auto',
                        opacity: updating ? 0.6 : 1 
                      }}
                    >
                      {(item.description || item.url).length > 20 
                        ? (item.description || item.url).substring(0, 20) + '...' 
                        : (item.description || item.url)
                      }
                    </a>
                  </h3>
                  <button
                    className="delete-button"
                    onClick={() => deleteItem(item.id)}
                    disabled={loading || updating}
                  >
                    削除
                  </button>
                </div>
                
                <div className="item-details">
                  {item.current_price !== null && (
                    <p>
                      <strong>現在価格:</strong> ¥{formatNumber(item.current_price)}
                      {item.points !== null && (
                        <span> ({formatNumber(item.points)}pt, {calculatePointRatio(item.current_price, item.points)}%)</span>
                      )}
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