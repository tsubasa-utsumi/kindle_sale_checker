import json
import boto3
import os
import uuid
import logging

# ロギング設定
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# DynamoDBクライアント（環境変数から取得）
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE', 'KindleItems'))

# CORSヘッダー
CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
}

# レスポンス作成ヘルパー
def create_response(status_code, body):
  return {
    'statusCode': status_code,
    'headers': CORS_HEADERS,
    'body': json.dumps(body, ensure_ascii=False)
  }

# アイテム一覧を取得
def get_all_items():
  response = table.scan()
  items = response.get('Items', [])
  # 型変換
  for item in items:
    if 'current_price' in item and item['current_price'] is not None:
      item['current_price'] = float(item['current_price'])
    if 'points' in item and item['points'] is not None:
      item['points'] = int(item['points'])
    if 'has_sale' in item and item['has_sale'] is not None:
      item['has_sale'] = bool(item['has_sale'])
  return items

# 単一アイテムを取得
def get_item(item_id):
  response = table.get_item(Key={'id': item_id})
  item = response.get('Item')
  # 型変換
  if item:
    if 'current_price' in item and item['current_price'] is not None:
      item['current_price'] = float(item['current_price'])
    if 'points' in item and item['points'] is not None:
      item['points'] = int(item['points'])
    if 'has_sale' in item and item['has_sale'] is not None:
      item['has_sale'] = bool(item['has_sale'])
  return item

# アイテムを作成
def create_item(url, description=None):
  item_id = str(uuid.uuid4())
  item = {
    'id': item_id,
    'url': url,
    'description': description or '',
    'has_sale': False,
    'current_price': None,
    'points': None
  }
  table.put_item(Item=item)
  return item

# アイテムを削除
def delete_item(item_id):
  response = table.delete_item(
    Key={'id': item_id},
    ReturnValues='ALL_OLD'
  )
  item = response.get('Attributes')
  # 型変換
  if item:
    if 'current_price' in item and item['current_price'] is not None:
      item['current_price'] = float(item['current_price'])
    if 'points' in item and item['points'] is not None:
      item['points'] = int(item['points'])
    if 'has_sale' in item and item['has_sale'] is not None:
      item['has_sale'] = bool(item['has_sale'])
  return item

# スクレイパーは独立したLambda関数として動作するため、
# API側からの呼び出しは行いません

# パスを正規化する (ステージプレフィックスを削除し、itemsエンドポイントを処理)
def normalize_path(path):
  logger.info(f"オリジナルパス: {path}")
  
  # 0. /apiを削除
  if path and path.startswith('/api'):
    path = path[len('/api'):]

  # 1. 先頭と末尾のスラッシュを削除
  path = path.strip('/')
  
  # 2. ステージプレフィックスを削除 (ステージを検出した場合のみ)
  # 例：'prod/items' -> 'items', 'dev/items/123' -> 'items/123'
  # items自体は削除しない！
  if '/' in path:
    parts = path.split('/', 1)
    # 先頭部分がステージと思われるか検証（items自体は削除しない）
    if len(parts) > 1 and parts[0] not in ['items']:
      # 最初のセグメントがステージと判断した場合のみ削除
      path = parts[1]
  
  # 3. パスがない場合のデフォルト
  if not path:
    path = ''
    
  logger.info(f"正規化後パス: {path}")
  return path

# リクエストからHTTPメソッドを取得（API Gateway V1/V2互換）
def get_http_method(event):
  # HTTP API (API Gateway V2)
  if 'requestContext' in event and 'http' in event['requestContext']:
    return event['requestContext']['http']['method']
  # REST API (API Gateway V1)
  elif 'httpMethod' in event:
    return event['httpMethod']
  # デフォルト
  return 'GET'

# リクエストからパスを取得（API Gateway V1/V2互換）
def get_path(event):
  # HTTP API (API Gateway V2)
  if 'requestContext' in event and 'http' in event['requestContext']:
    return event['requestContext']['http']['path']
  # REST API (API Gateway V1)
  elif 'path' in event:
    return event['path']
  # デフォルト
  return '/'

# メインのLambdaハンドラー
def lambda_handler(event, context):
  # イベントのデバッグ出力（開発時のみ）
  logger.info(f"Kindle Items API - イベント: {json.dumps(event)}")
  
  # HTTPメソッドとパスを取得
  http_method = get_http_method(event)
  path = get_path(event)
  
  logger.info(f"Kindle Items API - HTTPメソッド: {http_method}, パス: {path}")
  
  # プレフライトリクエスト処理
  if http_method == 'OPTIONS':
    return create_response(200, {})
    
  # パスを正規化
  normalized_path = normalize_path(path)
  
  # ルート (/) へのアクセス
  if normalized_path == '':
    # ルートエンドポイントへのGET
    if http_method == 'GET':
      return create_response(200, {'message': 'Kindle Items API is running. Use /items or /items/ to access the API.'})
  
  # itemsエンドポイント処理 (GET, POST)
  elif normalized_path == 'items':
    # アイテム一覧取得
    if http_method == 'GET':
      items = get_all_items()
      logger.info(f"取得アイテム数: {len(items)}")
      return create_response(200, items)
    
    # アイテム作成
    elif http_method == 'POST':
      try:
        # リクエストボディの取得（API Gateway V1/V2互換）
        if 'body' in event:
          body_str = event['body']
          if body_str is None:
            body_str = '{}'
        else:
          body_str = '{}'
        
        logger.info(f"リクエストボディ: {body_str}")
        
        body = json.loads(body_str)
        url = body.get('url')
        description = body.get('description', '')
        
        # 入力検証（URLのみ必須）
        if not url:
          return create_response(400, {'detail': 'URL is required'})
        
        item = create_item(url, description)
        return create_response(201, item)
      except json.JSONDecodeError as e:
        logger.error(f"JSONデコードエラー: {str(e)}")
        return create_response(400, {'detail': f'Invalid JSON in request body: {str(e)}'})
      except Exception as e:
        logger.error(f"アイテム作成エラー: {str(e)}")
        return create_response(500, {'detail': f'Error creating item: {str(e)}'})
  
  # 個別アイテム処理 (GET, DELETE)
  elif normalized_path.startswith('items/'):
    # /items/xxxx の形式からIDを抽出
    item_id = normalized_path.split('/', 1)[1]
    
    # アイテム詳細取得
    if http_method == 'GET':
      item = get_item(item_id)
      if not item:
        return create_response(404, {'detail': 'Item not found'})
      return create_response(200, item)
    
    # アイテム削除
    elif http_method == 'DELETE':
      item = delete_item(item_id)
      if not item:
        return create_response(404, {'detail': 'Item not found'})
      return create_response(200, item)
  
  # 一致するルートが見つからない
  logger.warning(f"一致するルートが見つかりません: method={http_method}, path={normalized_path}")
  return create_response(404, {'detail': 'Not Found'})

# 互換性用のハンドラー
def handler(event, context):
  return lambda_handler(event, context)