// frontend/src/AuthComponent.js (完全クリーン版)
import React, { useState } from 'react';
import { signIn, setNewPassword } from './authService';
import './Auth.css';

const AuthComponent = ({ onAuthSuccess }) => {
  const [mode, setMode] = useState('signin'); // 'signin', 'newpassword'のみ
  const [formData, setFormData] = useState({
    email: '',
    password: '',
    newPassword: '',
    confirmNewPassword: ''
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [pendingEmail, setPendingEmail] = useState('');
  const [cognitoUser, setCognitoUser] = useState(null); // 新パスワード設定用

  const handleInputChange = (e) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value
    });
    setError(''); // エラーをクリア
  };

  const handleSignIn = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      await signIn(formData.email, formData.password);
      onAuthSuccess();
    } catch (error) {
      console.error('サインインエラー:', error);
      if (error.code === 'UserNotConfirmedException') {
        setError('アカウントが確認されていません。管理者にお問い合わせください。');
      } else if (error.code === 'NotAuthorizedException') {
        setError('メールアドレスまたはパスワードが正しくありません。');
      } else if (error.code === 'UserNotFoundException') {
        setError('ユーザーが見つかりません。管理者にお問い合わせください。');
      } else if (error.name === 'NewPasswordRequiredError' || error.message === '新しいパスワードの設定が必要です') {
        // 新しいパスワードが必要な場合
        setCognitoUser(error.cognitoUser || error.user);
        setPendingEmail(formData.email);
        setMode('newpassword');
        setError('');
      } else {
        setError(`ログインに失敗しました: ${error.message}`);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleNewPassword = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    if (formData.newPassword !== formData.confirmNewPassword) {
      setError('パスワードが一致しません。');
      setLoading(false);
      return;
    }

    if (formData.newPassword.length < 8) {
      setError('パスワードは8文字以上で入力してください。');
      setLoading(false);
      return;
    }

    try {
      // authServiceの新パスワード設定関数を呼び出し
      await setNewPassword(cognitoUser, formData.newPassword);
      alert('パスワードが設定されました。再度ログインしてください。');
      setMode('signin');
      setCognitoUser(null);
      setFormData({
        email: '',
        password: '',
        newPassword: '',
        confirmNewPassword: ''
      });
    } catch (error) {
      console.error('新パスワード設定エラー:', error);
      if (error.code === 'InvalidPasswordException') {
        setError('パスワードの要件を満たしていません。8文字以上、英数字を含める必要があります。');
      } else {
        setError(`パスワードの設定に失敗しました: ${error.message}`);
      }
    } finally {
      setLoading(false);
    }
  };

  const renderSignInForm = () => (
    <form onSubmit={handleSignIn} className="auth-form">
      <h2>ログイン</h2>
      
      <div className="form-group">
        <label htmlFor="email">メールアドレス:</label>
        <input
          type="email"
          id="email"
          name="email"
          value={formData.email}
          onChange={handleInputChange}
          required
          disabled={loading}
          placeholder="example@email.com"
        />
      </div>

      <div className="form-group">
        <label htmlFor="password">パスワード:</label>
        <input
          type="password"
          id="password"
          name="password"
          value={formData.password}
          onChange={handleInputChange}
          required
          disabled={loading}
          placeholder="パスワードを入力"
        />
      </div>

      <button type="submit" disabled={loading} className="auth-button">
        {loading ? 'ログイン中...' : 'ログイン'}
      </button>
    </form>
  );

  const renderNewPasswordForm = () => (
    <form onSubmit={handleNewPassword} className="auth-form">
      <h2>新しいパスワードを設定</h2>
      
      <p className="confirm-message">
        {pendingEmail} のパスワードを設定してください。
      </p>

      <div className="form-group">
        <label htmlFor="newPassword">新しいパスワード:</label>
        <input
          type="password"
          id="newPassword"
          name="newPassword"
          value={formData.newPassword}
          onChange={handleInputChange}
          required
          disabled={loading}
          placeholder="8文字以上の英数字"
        />
      </div>

      <div className="form-group">
        <label htmlFor="confirmNewPassword">パスワード確認:</label>
        <input
          type="password"
          id="confirmNewPassword"
          name="confirmNewPassword"
          value={formData.confirmNewPassword}
          onChange={handleInputChange}
          required
          disabled={loading}
          placeholder="パスワードを再入力"
        />
      </div>

      <button type="submit" disabled={loading} className="auth-button">
        {loading ? 'パスワード設定中...' : 'パスワードを設定'}
      </button>

      <div className="confirm-actions">
        <button 
          type="button" 
          onClick={() => setMode('signin')} 
          className="link-button"
          disabled={loading}
        >
          ログインに戻る
        </button>
      </div>
    </form>
  );

  return (
    <div className="auth-container">
      <div className="auth-card">
        <div className="auth-header">
          <h1>Kindle Sale Checker</h1>
          <p>Kindleの本のセール情報をチェック</p>
        </div>

        {error && <div className="error-message">{error}</div>}

        {mode === 'signin' && renderSignInForm()}
        {mode === 'newpassword' && renderNewPasswordForm()}
      </div>
    </div>
  );
};

export default AuthComponent;