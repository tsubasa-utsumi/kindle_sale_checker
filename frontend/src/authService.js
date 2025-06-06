// frontend/src/authService.js (環境変数対応版)
import { 
  CognitoUserPool, 
  CognitoUser, 
  AuthenticationDetails,
  CognitoUserAttribute
} from 'amazon-cognito-identity-js';

// 環境変数から設定を取得（フォールバック値付き）
const getUserPoolId = () => {
  return process.env.REACT_APP_COGNITO_USER_POOL_ID || 'TERRAFORM_USER_POOL_ID_PLACEHOLDER';
};

const getClientId = () => {
  return process.env.REACT_APP_COGNITO_CLIENT_ID || 'TERRAFORM_CLIENT_ID_PLACEHOLDER';
};

const getAWSRegion = () => {
  return process.env.REACT_APP_AWS_REGION || 'ap-northeast-1';
};

// Cognito設定
const poolData = {
  UserPoolId: getUserPoolId(),
  ClientId: getClientId()
};

const userPool = new CognitoUserPool(poolData);

// ローカルストレージのキー
const TOKEN_KEY = 'cognito_tokens';
const USER_KEY = 'cognito_user';

/**
 * Cognito設定を取得する（デバッグ用）
 */
export const getCognitoSettings = () => {
  return {
    userPoolId: poolData.UserPoolId,
    clientId: poolData.ClientId,
    region: getAWSRegion(),
    isConfiguredFromEnv: !!(process.env.REACT_APP_COGNITO_USER_POOL_ID && process.env.REACT_APP_COGNITO_CLIENT_ID)
  };
};

/**
 * 設定の有効性をチェック
 */
export const validateConfiguration = () => {
  const settings = getCognitoSettings();
  
  const isValid = {
    userPoolId: settings.userPoolId !== 'TERRAFORM_USER_POOL_ID_PLACEHOLDER' && settings.userPoolId.length > 0,
    clientId: settings.clientId !== 'TERRAFORM_CLIENT_ID_PLACEHOLDER' && settings.clientId.length > 0,
    configured: settings.isConfiguredFromEnv
  };
  
  if (process.env.REACT_APP_DEBUG_MODE === 'true') {
    console.log('Cognito Configuration Status:', {
      ...settings,
      isValid
    });
  }
  
  return isValid;
};

/**
 * ユーザー新規登録
 */
export const signUp = (email, password) => {
  return new Promise((resolve, reject) => {
    const validation = validateConfiguration();
    if (!validation.userPoolId || !validation.clientId) {
      reject(new Error('Cognito設定が正しく構成されていません。'));
      return;
    }

    const attributeList = [
      new CognitoUserAttribute({
        Name: 'email',
        Value: email
      })
    ];

    userPool.signUp(email, password, attributeList, null, (err, result) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(result);
    });
  });
};

/**
 * 確認コードによるアカウント確認
 */
export const confirmSignUp = (email, confirmationCode) => {
  return new Promise((resolve, reject) => {
    const validation = validateConfiguration();
    if (!validation.userPoolId || !validation.clientId) {
      reject(new Error('Cognito設定が正しく構成されていません。'));
      return;
    }

    const cognitoUser = new CognitoUser({
      Username: email,
      Pool: userPool
    });

    cognitoUser.confirmRegistration(confirmationCode, true, (err, result) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(result);
    });
  });
};

/**
 * 確認コード再送信
 */
export const resendConfirmationCode = (email) => {
  return new Promise((resolve, reject) => {
    const validation = validateConfiguration();
    if (!validation.userPoolId || !validation.clientId) {
      reject(new Error('Cognito設定が正しく構成されていません。'));
      return;
    }

    const cognitoUser = new CognitoUser({
      Username: email,
      Pool: userPool
    });

    cognitoUser.resendConfirmationCode((err, result) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(result);
    });
  });
};

/**
 * ユーザーサインイン
 */
export const signIn = (email, password) => {
  return new Promise((resolve, reject) => {
    const validation = validateConfiguration();
    if (!validation.userPoolId || !validation.clientId) {
      reject(new Error('Cognito設定が正しく構成されていません。環境変数を確認してください。'));
      return;
    }

    const authenticationDetails = new AuthenticationDetails({
      Username: email,
      Password: password
    });

    const cognitoUser = new CognitoUser({
      Username: email,
      Pool: userPool
    });

    cognitoUser.authenticateUser(authenticationDetails, {
      onSuccess: (result) => {
        // トークンをローカルストレージに保存
        const tokens = {
          accessToken: result.getAccessToken().getJwtToken(),
          idToken: result.getIdToken().getJwtToken(),
          refreshToken: result.getRefreshToken().getToken(),
          expiration: result.getAccessToken().getExpiration() * 1000 // ミリ秒に変換
        };
        
        localStorage.setItem(TOKEN_KEY, JSON.stringify(tokens));
        
        // ユーザー情報を保存
        const userInfo = {
          email: result.getIdToken().payload.email,
          sub: result.getIdToken().payload.sub
        };
        localStorage.setItem(USER_KEY, JSON.stringify(userInfo));
        
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.log('サインイン成功:', userInfo);
        }
        resolve(result);
      },
      onFailure: (err) => {
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.error('サインインエラー:', err);
        }
        reject(err);
      },
      newPasswordRequired: (userAttributes, requiredAttributes) => {
        // 新しいパスワードが必要な場合
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.log('新しいパスワードが必要です');
        }
        const error = new Error('新しいパスワードの設定が必要です');
        error.name = 'NewPasswordRequiredError';
        error.cognitoUser = cognitoUser;
        error.userAttributes = userAttributes;
        error.requiredAttributes = requiredAttributes;
        reject(error);
      }
    });
  });
};

/**
 * 新しいパスワードを設定
 */
export const setNewPassword = (cognitoUser, newPassword) => {
  return new Promise((resolve, reject) => {
    if (!cognitoUser) {
      reject(new Error('CognitoUserオブジェクトが必要です'));
      return;
    }

    cognitoUser.completeNewPasswordChallenge(newPassword, {}, {
      onSuccess: (result) => {
        // トークンをローカルストレージに保存
        const tokens = {
          accessToken: result.getAccessToken().getJwtToken(),
          idToken: result.getIdToken().getJwtToken(),
          refreshToken: result.getRefreshToken().getToken(),
          expiration: result.getAccessToken().getExpiration() * 1000
        };
        
        localStorage.setItem(TOKEN_KEY, JSON.stringify(tokens));
        
        // ユーザー情報を保存
        const userInfo = {
          email: result.getIdToken().payload.email,
          sub: result.getIdToken().payload.sub
        };
        localStorage.setItem(USER_KEY, JSON.stringify(userInfo));
        
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.log('新しいパスワード設定成功:', userInfo);
        }
        resolve(result);
      },
      onFailure: (err) => {
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.error('新しいパスワード設定エラー:', err);
        }
        reject(err);
      }
    });
  });
};

/**
 * 現在のユーザー情報を取得
 */
export const getCurrentUser = () => {
  return new Promise((resolve, reject) => {
    const validation = validateConfiguration();
    if (!validation.userPoolId || !validation.clientId) {
      reject(new Error('Cognito設定が正しく構成されていません。'));
      return;
    }

    const cognitoUser = userPool.getCurrentUser();
    
    if (!cognitoUser) {
      // ローカルストレージからも確認
      const userInfo = localStorage.getItem(USER_KEY);
      if (userInfo) {
        try {
          resolve(JSON.parse(userInfo));
          return;
        } catch (e) {
          if (process.env.REACT_APP_DEBUG_MODE === 'true') {
            console.error('ユーザー情報の解析エラー:', e);
          }
        }
      }
      reject(new Error('ユーザーが見つかりません'));
      return;
    }

    cognitoUser.getSession((err, session) => {
      if (err) {
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.error('セッション取得エラー:', err);
        }
        // ローカルストレージをクリア
        localStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(USER_KEY);
        reject(err);
        return;
      }

      if (!session.isValid()) {
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.log('セッションが無効です');
        }
        // トークンをリフレッシュしてみる
        refreshToken()
          .then(() => {
            // リフレッシュ成功後、再度ユーザー情報を取得
            const userInfo = localStorage.getItem(USER_KEY);
            if (userInfo) {
              resolve(JSON.parse(userInfo));
            } else {
              reject(new Error('ユーザー情報が見つかりません'));
            }
          })
          .catch(reject);
        return;
      }

      // ユーザー情報を取得
      const userInfo = {
        email: session.getIdToken().payload.email,
        sub: session.getIdToken().payload.sub
      };

      // ローカルストレージに保存
      localStorage.setItem(USER_KEY, JSON.stringify(userInfo));
      
      resolve(userInfo);
    });
  });
};

/**
 * IDトークンを取得（APIリクエスト用）
 */
export const getIdToken = () => {
  return new Promise((resolve, reject) => {
    const validation = validateConfiguration();
    if (!validation.userPoolId || !validation.clientId) {
      reject(new Error('Cognito設定が正しく構成されていません。'));
      return;
    }

    // まずローカルストレージから取得を試みる
    const tokens = localStorage.getItem(TOKEN_KEY);
    if (tokens) {
      try {
        const parsedTokens = JSON.parse(tokens);
        const now = Date.now();
        
        // トークンがまだ有効かチェック（有効期限の5分前までを有効とする）
        if (parsedTokens.expiration && parsedTokens.expiration > now + 300000) {
          resolve(parsedTokens.idToken);
          return;
        }
      } catch (e) {
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.error('トークンの解析エラー:', e);
        }
      }
    }

    // ローカルストレージのトークンが無効または期限切れの場合、Cognitoから取得
    const cognitoUser = userPool.getCurrentUser();
    
    if (!cognitoUser) {
      reject(new Error('ユーザーが見つかりません'));
      return;
    }

    cognitoUser.getSession((err, session) => {
      if (err) {
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.error('セッション取得エラー:', err);
        }
        reject(err);
        return;
      }

      if (!session.isValid()) {
        // セッションが無効な場合、リフレッシュトークンで更新
        refreshToken()
          .then(() => getIdToken())
          .then(resolve)
          .catch(reject);
        return;
      }

      const idToken = session.getIdToken().getJwtToken();
      
      // 新しいトークンをローカルストレージに保存
      const tokens = {
        accessToken: session.getAccessToken().getJwtToken(),
        idToken: idToken,
        refreshToken: session.getRefreshToken().getToken(),
        expiration: session.getAccessToken().getExpiration() * 1000
      };
      localStorage.setItem(TOKEN_KEY, JSON.stringify(tokens));
      
      resolve(idToken);
    });
  });
};

/**
 * リフレッシュトークンを使ってトークンを更新
 */
export const refreshToken = () => {
  return new Promise((resolve, reject) => {
    const cognitoUser = userPool.getCurrentUser();
    
    if (!cognitoUser) {
      reject(new Error('ユーザーが見つかりません'));
      return;
    }

    cognitoUser.getSession((err, session) => {
      if (err) {
        reject(err);
        return;
      }

      // リフレッシュトークンを使用してセッションを更新
      const refreshTokenObj = session.getRefreshToken();
      
      cognitoUser.refreshSession(refreshTokenObj, (err, session) => {
        if (err) {
          if (process.env.REACT_APP_DEBUG_MODE === 'true') {
            console.error('トークンリフレッシュエラー:', err);
          }
          // リフレッシュに失敗した場合、ローカルストレージをクリア
          localStorage.removeItem(TOKEN_KEY);
          localStorage.removeItem(USER_KEY);
          reject(err);
          return;
        }

        // 新しいトークンをローカルストレージに保存
        const tokens = {
          accessToken: session.getAccessToken().getJwtToken(),
          idToken: session.getIdToken().getJwtToken(),
          refreshToken: session.getRefreshToken().getToken(),
          expiration: session.getAccessToken().getExpiration() * 1000
        };
        localStorage.setItem(TOKEN_KEY, JSON.stringify(tokens));
        
        if (process.env.REACT_APP_DEBUG_MODE === 'true') {
          console.log('トークンをリフレッシュしました');
        }
        resolve(session);
      });
    });
  });
};

/**
 * サインアウト
 */
export const signOut = () => {
  return new Promise((resolve) => {
    const cognitoUser = userPool.getCurrentUser();
    
    if (cognitoUser) {
      cognitoUser.signOut();
    }
    
    // ローカルストレージをクリア
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
    
    if (process.env.REACT_APP_DEBUG_MODE === 'true') {
      console.log('サインアウトしました');
    }
    resolve();
  });
};

/**
 * トークンの自動リフレッシュを設定
 */
export const setupAutoRefresh = () => {
  // 30分ごとにトークンの有効性をチェックし、必要に応じてリフレッシュ
  setInterval(async () => {
    try {
      const tokens = localStorage.getItem(TOKEN_KEY);
      if (tokens) {
        const parsedTokens = JSON.parse(tokens);
        const now = Date.now();
        
        // 有効期限の10分前になったらリフレッシュ
        if (parsedTokens.expiration && parsedTokens.expiration <= now + 600000) {
          if (process.env.REACT_APP_DEBUG_MODE === 'true') {
            console.log('トークンの自動リフレッシュを実行します');
          }
          await refreshToken();
        }
      }
    } catch (error) {
      if (process.env.REACT_APP_DEBUG_MODE === 'true') {
        console.error('自動リフレッシュエラー:', error);
      }
    }
  }, 30 * 60 * 1000); // 30分
};