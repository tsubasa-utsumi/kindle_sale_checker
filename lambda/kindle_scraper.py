import boto3
from bs4 import BeautifulSoup
from datetime import datetime, timedelta
import json
import logging
import os
import random
import re
import requests
import time
from linebot import LineBotApi
from linebot.exceptions import LineBotApiError
from linebot.models import FlexSendMessage, TextSendMessage
from typing import Any, Dict, List

# ロギング設定
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ユーザーエージェント
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"
]
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
    "Accept-Language": "ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7"
}

# LINE Messaging API 設定
LINE_CHANNEL_ACCESS_TOKEN = os.environ.get('LINE_CHANNEL_ACCESS_TOKEN', '')
LINE_USER_ID = os.environ.get('LINE_USER_ID', '')  # 通知を送信するユーザーID

# 通知間隔設定（7日 = 1週間）
NOTIFICATION_INTERVAL_DAYS = 7

# 更新ロック用の特別なID
UPDATE_LOCK_ID = '__UPDATE_LOCK__'
LOCK_TTL_HOURS = 0  # 1時間

def is_already_running(table):
    """
    既にスクレイパーが実行中かどうかを確認する
    既存テーブルの特別なレコードで実行中フラグを管理
    """
    try:
        # 更新ロックレコードを確認
        response = table.get_item(
            Key={'id': UPDATE_LOCK_ID}
        )
        
        if 'Item' in response:
            item = response['Item']
            started_at = item.get('started_at')
            
            if started_at:
                try:
                    # ISO形式の文字列をdatetimeオブジェクトに変換（UTC前提）
                    start_time = datetime.fromisoformat(started_at.replace('Z', ''))
                    current_time = datetime.utcnow()
                    
                    elapsed_seconds = (current_time - start_time).total_seconds()
                    elapsed_hours = elapsed_seconds / 3600
                    
                    logger.info(f"ロック状態チェック - 開始時刻: {started_at}, 現在時刻: {current_time.isoformat()}Z, 経過時間: {elapsed_hours:.2f}時間")
                    
                    # TTL時間内の場合は実行中と判定
                    if elapsed_hours < LOCK_TTL_HOURS and elapsed_hours >= 0:
                        logger.info(f"スクレイパーが既に実行中です。経過時間: {elapsed_hours:.2f}時間")
                        return True
                    else:
                        logger.info(f"前回の実行から{elapsed_hours:.2f}時間が経過したため、ロックを解除します")
                        # 期限切れのロックを削除
                        table.delete_item(Key={'id': UPDATE_LOCK_ID})
                except (ValueError, TypeError) as e:
                    logger.warning(f"実行時間の解析に失敗: {str(e)}, started_at: {started_at}")
                    # 不正なレコードは削除
                    table.delete_item(Key={'id': UPDATE_LOCK_ID})
        
        return False
        
    except Exception as e:
        logger.error(f"実行中フラグの確認でエラーが発生: {str(e)}")
        # エラーの場合は安全のため実行を許可しない
        return True

def set_update_lock(table, function_name):
    """
    実行中フラグを設定する
    """
    try:
        # UTC時刻で統一
        current_time = datetime.utcnow()
        expires_at = current_time + timedelta(hours=LOCK_TTL_HOURS)
        
        # ISO形式で統一（UTC）
        current_time_str = current_time.isoformat() + 'Z'  # Zを付けてUTCであることを明示
        expires_at_str = expires_at.isoformat() + 'Z'
        
        table.put_item(
            Item={
                'id': UPDATE_LOCK_ID,
                'status': 'running',
                'started_at': current_time_str,
                'expires_at': expires_at_str,
                'function_name': function_name,
                'description': 'Kindle scraper update lock',
                'created_by': 'kindle_scraper'
            }
        )
        
        logger.info(f"実行中フラグを設定しました: {current_time_str} (TTL: {LOCK_TTL_HOURS}時間)")
        return True
        
    except Exception as e:
        logger.error(f"実行中フラグの設定でエラーが発生: {str(e)}")
        return False

def clear_update_lock(table):
    """
    実行中フラグをクリアする
    """
    try:
        table.delete_item(
            Key={'id': UPDATE_LOCK_ID}
        )
        
        logger.info("実行中フラグをクリアしました")
        return True
        
    except Exception as e:
        logger.error(f"実行中フラグのクリアでエラーが発生: {str(e)}")
        return False

def scan_all_items(table) -> List[Dict[str, Any]]:
    """
    DynamoDBテーブルからすべてのアイテムを取得する
    ページネーションを処理して大量のアイテムを扱えるようにする
    更新ロックレコードは除外する
    """
    items = []
    scan_kwargs = {}
    done = False
    
    while not done:
        response = table.scan(**scan_kwargs)
        
        # 更新ロックレコード以外のアイテムのみを追加
        for item in response.get('Items', []):
            if item.get('id') != UPDATE_LOCK_ID:
                items.append(item)
        
        # 続きのアイテムがあるか確認
        if 'LastEvaluatedKey' in response:
            scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']
        else:
            done = True
    
    return items

def update_item(table, items) -> bool:
    """
    指定されたIDのアイテムを更新する
    """
    current_time = datetime.now().isoformat()
    for item in items:
        try:
            # 更新ロックレコードはスキップ
            if item.get('id') == UPDATE_LOCK_ID:
                continue
                
            update_expression = 'SET current_price = :price, description = :desc, has_sale = :sale, points = :pts, updated_at = :upd'
            expression_attribute_values = {
                ':price': item['current_price'],
                ':desc': item['description'],
                ':sale': item['has_sale'],
                ':pts': item['points'],
                ':upd': current_time
            }
            
            # 通知履歴があれば更新
            if 'last_notification' in item:
                update_expression += ', last_notification = :notif'
                expression_attribute_values[':notif'] = item['last_notification']
            
            res = table.update_item(
                Key={'id': item['id']},
                UpdateExpression=update_expression,
                ExpressionAttributeValues=expression_attribute_values,
                ReturnValues='UPDATED_NEW'
            )
        except Exception as e:
            logger.error(f"Failed to update item {item['id']}: {str(e)}")

def parse_price(text):
    """テキストから価格（円）を抽出する（例: "￥653" -> 653）"""
    if not text:
        return None
    price_match = re.search(r'￥\s*([0-9,]+)', text)
    return int(price_match.group(1).replace(',', '')) if price_match else None

def parse_points(text):
    """テキストからポイント数を抽出する（例: "(7pt)" -> 7）"""
    if not text:
        return 0
    point_match = re.search(r'([0-9,]+)\s*pt', text)
    return int(point_match.group(1).replace(',', '')) if point_match else 0

def extract_price_and_points(soup):
    """
    Amazonページから現在価格とポイント還元数を取得する。
    Kindle Unlimited対象本は表示価格が「￥0」になるため、
    「または￥XXX (Xpt)で購入」に記載された実際の購入価格を取得する。
    戻り値: (current_price, point_value)
    """
    # Kindle版のフォーマットスワッチを優先的に参照する
    kindle_swatch = soup.select_one("#tmm-grid-swatch-KINDLE")

    if kindle_swatch:
        slot_price_elem = kindle_swatch.select_one(".slot-price")
        slot_price = parse_price(slot_price_elem.text) if slot_price_elem else None

        # Kindle Unlimited対象（￥0表示）かどうかを判定
        is_kindle_unlimited = kindle_swatch.select_one(".a-icon-kindle-unlimited") is not None

        if is_kindle_unlimited or slot_price == 0:
            # 「または￥XXX (Xpt)で購入」から実際の購入価格・ポイントを取得
            extra_elem = kindle_swatch.select_one(".kindleExtraMessage")
            if extra_elem:
                purchase_price = parse_price(extra_elem.text)
                purchase_points = parse_points(extra_elem.text)
                if purchase_price is not None:
                    return purchase_price, purchase_points

        # 通常表示の価格が取得できた場合はそれを使う
        if slot_price is not None and slot_price > 0:
            points_elem = kindle_swatch.select_one(".slot-buyingPoints")
            point_value = parse_points(points_elem.text) if points_elem else 0
            return slot_price, point_value

    # フォールバック: 従来のセレクタで取得
    current_price_elem = soup.select_one(".kindle-price .a-color-price")
    if not current_price_elem:
        current_price_elem = soup.select_one(".a-color-price")
    current_price = parse_price(current_price_elem.text) if current_price_elem else None

    point_elem = soup.select_one(".slot-buyingPoints")
    point_value = parse_points(point_elem.text) if point_elem else 0

    return current_price, point_value

def get_kindle_info(item):
    """Amazonページから本の情報を取得する"""
    try:
        response = requests.get(item, headers=HEADERS)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')

        # 書籍タイトルを取得
        title = soup.select_one("#productTitle")
        title = title.text.strip() if title else "タイトル不明"

        # 価格とポイント還元情報を取得（Kindle Unlimited対応）
        current_price, point_value = extract_price_and_points(soup)

        return {
            "title": title,
            "current_price": current_price,
            "list_price": current_price,
            "point_value": point_value,
            "item": item
        }
        
    except Exception as e:
        logger.error(f"item {item} の処理中にエラーが発生: {e}")
        return None

def calculate_discount_percentage(current_price, list_price, point_value):
    """割引率を計算する (ポイント還元含む)"""
    if not current_price or not list_price:
        return 0
    
    # 型変換
    current_price = float(current_price)
    list_price = float(list_price)
    point_value = float(point_value)
    
    effective_price = current_price - point_value
    discount = list_price - effective_price
    discount_percentage = (discount / list_price) * 100 if list_price > 0 else 0
    
    return discount_percentage

def should_notify(item, current_price, point_value):
    """通知すべきかどうかを判断する（1週間以内に通知済みかと割引率のチェック）"""
    # 1. 前回の通知日時をチェック
    should_send = True
    last_notification = item.get('last_notification')
    
    if last_notification:
        # ISO形式の文字列をdatetimeオブジェクトに変換
        try:
            last_notification_date = datetime.fromisoformat(last_notification)
            now = datetime.now()
            elapsed_days = (now - last_notification_date).total_seconds() / (24 * 3600)
            
            logger.info(f"アイテム「{item.get('description', 'Unknown')}」の前回通知からの経過日数: {elapsed_days:.1f}日")
            
            # 1週間以内の通知はスキップの対象に
            if elapsed_days < NOTIFICATION_INTERVAL_DAYS:
                # 前回と今回の価格を比較
                last_price = item.get('current_price')
                last_points = item.get('points', 0)
                
                if last_price is not None and current_price is not None:
                    # 型変換 (DynamoDBから取得した数値はDecimal型の場合がある)
                    # decimal.Decimal型をfloatに変換する
                    if hasattr(last_price, 'to_eng_string'):  # Decimalかどうかを確認
                        last_price = float(last_price)
                    else:
                        last_price = float(last_price)
                        
                    if hasattr(last_points, 'to_eng_string'):  # Decimalかどうかを確認
                        last_points = float(last_points)
                    else:
                        last_points = float(last_points)
                    
                    # 実質価格の計算（すべてfloatに変換）
                    last_effective_price = float(last_price) - float(last_points)
                    current_effective_price = float(current_price) - float(point_value)
                    
                    price_diff_percentage = ((last_effective_price - current_effective_price) / last_effective_price) * 100 if last_effective_price > 0 else 0
                    
                    logger.info(f"価格比較: 前回={last_effective_price}円（実質）, 今回={current_effective_price}円（実質）, 変化率={price_diff_percentage:.1f}%")
                    
                    # 実質価格が前回より10%以上安くなった場合のみ再通知
                    if current_effective_price >= last_effective_price * 0.9:
                        # 価格が同じか高くなった場合はスキップ
                        should_send = False
                        logger.info(f"前回の通知から{elapsed_days:.1f}日しか経っておらず、価格に大きな変動がないため通知をスキップします")
                    else:
                        logger.info(f"前回の通知から{elapsed_days:.1f}日ですが、価格が大幅に下がったため再通知します")
        except (ValueError, TypeError) as e:
            # 日付の解析に失敗した場合はログに記録し、通知を許可
            logger.warning(f"日付の解析に失敗しました: {str(e)}")
            logger.warning(f"エラーが発生したアイテム: {item}")
    
    return should_send

def check_kindle_sales(items, table):
    """セール情報を確認し、条件に合うものを通知する"""
    sale_items = []
    sale_percentage = float(os.environ.get('SALE_PERCENTAGE', '20'))
    sale_price = int(os.environ.get('SALE_PRICE', '500'))

    # 対象の配列をシャッフル
    random.shuffle(items)

    for item in items:
        kindle_info = get_kindle_info(item['url'])
        
        if not kindle_info:
            continue
            
        if kindle_info["current_price"] is None or kindle_info["list_price"] is None:
            logger.info(f"価格情報を取得できませんでした: {kindle_info['title']}")
            continue
        
        current_price = kindle_info["current_price"]
        list_price = kindle_info["list_price"]
        point_value = kindle_info["point_value"]
        
        # 割引率を計算
        discount_percentage = calculate_discount_percentage(
            current_price, 
            list_price,
            point_value
        )

        has_sale = False
        if discount_percentage >= sale_percentage or current_price <= sale_price:
            logger.info(f"タイトル: {kindle_info['title']}, item: {kindle_info['item']}")
            
            # 通知条件を満たしているが、最近通知したかどうかをチェック
            should_send_notification = should_notify(item, current_price, point_value)
            
            if should_send_notification:
                sale_item = {
                    "id": item['id'],
                    "title": kindle_info['title'],
                    "current_price": current_price,
                    "list_price": list_price,
                    "point_value": point_value,
                    "effective_price": current_price - point_value,
                    "discount_percentage": discount_percentage,
                    "item": kindle_info['item']
                }
                sale_items.append(sale_item)
                
                # 通知情報を更新
                item['last_notification'] = datetime.now().isoformat()
            
            has_sale = True
        else:
            logger.info(f"タイトル: {kindle_info['title']}")

        # 取得した情報を格納
        item['current_price'] = current_price
        item['description'] = kindle_info['title']
        item['has_sale'] = has_sale
        item['points'] = point_value
        
        # Amazonのレート制限を回避するために少し待機
        random_value = random.uniform(0.3, 1)
        time.sleep(random_value)
        
    return sale_items

def format_text_message(sale_items):
    """テキストメッセージを整形する（Flex Messageが使えない場合用）"""
    if not sale_items:
        return "セール対象の商品はありませんでした。"
    
    message = "📚 Kindleセール情報 📚\n\n"
    for item in sale_items:
        message += f"{item['title']}\n"
        message += f"定価：¥{item['list_price']:,}、現在価格：¥{item['current_price']:,}\n"
        message += f"ポイント：{item['point_value']}pt（{item['discount_percentage']:.1f}%オフ）\n"
        message += f"{item['item']}\n\n"
    
    return message

def create_flex_message(sale_items):
    """LINE Flex Messageを作成する"""
    contents = {
        "type": "carousel",
        "contents": []
    }
    
    for item in sale_items:
        bubble = {
            "type": "bubble",
            "header": {
                "type": "box",
                "layout": "vertical",
                "contents": [
                    {
                        "type": "text",
                        "text": f"{item['discount_percentage']:.1f}%オフ",
                        "color": "#ffffff",
                        "weight": "bold",
                        "size": "xl"
                    }
                ],
                "backgroundColor": "#DD3333"
            },
            "body": {
                "type": "box",
                "layout": "vertical",
                "contents": [
                    {
                        "type": "text",
                        "text": item['title'],
                        "weight": "bold",
                        "size": "md",
                        "wrap": True,
                        "maxLines": 2
                    },
                    {
                        "type": "box",
                        "layout": "vertical",
                        "margin": "lg",
                        "contents": [
                            {
                                "type": "box",
                                "layout": "baseline",
                                "contents": [
                                    {
                                        "type": "text",
                                        "text": "定価",
                                        "color": "#999999",
                                        "size": "sm",
                                        "flex": 1
                                    },
                                    {
                                        "type": "text",
                                        "text": f"¥{item['list_price']:,}",
                                        "color": "#999999",
                                        "size": "sm",
                                        "decoration": "line-through",
                                        "flex": 2
                                    }
                                ]
                            },
                            {
                                "type": "box",
                                "layout": "baseline",
                                "contents": [
                                    {
                                        "type": "text",
                                        "text": "現在価格",
                                        "color": "#333333",
                                        "size": "sm",
                                        "flex": 1
                                    },
                                    {
                                        "type": "text",
                                        "text": f"¥{item['current_price']:,}",
                                        "color": "#333333",
                                        "size": "sm",
                                        "flex": 2
                                    }
                                ]
                            },
                            {
                                "type": "box",
                                "layout": "baseline",
                                "contents": [
                                    {
                                        "type": "text",
                                        "text": "ポイント",
                                        "color": "#333333",
                                        "size": "sm",
                                        "flex": 1
                                    },
                                    {
                                        "type": "text",
                                        "text": f"{item['point_value']}pt",
                                        "color": "#333333",
                                        "size": "sm",
                                        "flex": 2
                                    }
                                ]
                            },
                            {
                                "type": "box",
                                "layout": "baseline",
                                "contents": [
                                    {
                                        "type": "text",
                                        "text": "実質価格",
                                        "color": "#DD3333",
                                        "size": "sm",
                                        "weight": "bold",
                                        "flex": 1
                                    },
                                    {
                                        "type": "text",
                                        "text": f"¥{item['effective_price']:,}",
                                        "color": "#DD3333",
                                        "size": "sm",
                                        "weight": "bold",
                                        "flex": 2
                                    }
                                ]
                            }
                        ]
                    }
                ]
            },
            "footer": {
                "type": "box",
                "layout": "vertical",
                "contents": [
                    {
                        "type": "button",
                        "style": "primary",
                        "action": {
                            "type": "uri",
                            "label": "商品を見る",
                            "uri": item['item']
                        }
                    }
                ]
            }
        }
        contents["contents"].append(bubble)
    
    return contents

def send_line_message(sale_items):
    """LINE Messaging APIで通知を送信する"""
    if not LINE_CHANNEL_ACCESS_TOKEN or not LINE_USER_ID:
        logger.warning("LINE Channel Access TokenまたはUser IDが設定されていません。通知は送信されません。")
        return False
    
    try:
        line_bot_api = LineBotApi(LINE_CHANNEL_ACCESS_TOKEN)
        
        # セール商品がある場合
        if sale_items:
            # まず通常のテキストメッセージを送信
            text_message = f"📚 {len(sale_items)}冊のKindleセール本が見つかりました！"
            line_bot_api.push_message(
                LINE_USER_ID, 
                TextSendMessage(text=text_message)
            )
            
            # Flex Messageを送信（リッチメッセージ）
            try:
                flex_contents = create_flex_message(sale_items)
                flex_message = FlexSendMessage(
                    alt_text='Kindleセール情報',
                    contents=flex_contents
                )
                logger.info(f"flex_contents length: {len(flex_contents)}")
                line_bot_api.push_message(LINE_USER_ID, flex_message)
            except Exception as flex_error:
                # Flex Messageが送信できない場合はテキストで送信
                logger.warning(f"Flex Message送信エラー: {flex_error}")
                text_content = format_text_message(sale_items)
                line_bot_api.push_message(
                    LINE_USER_ID,
                    TextSendMessage(text=text_content)
                )
        else:
            # セール商品がない場合は通知しない
            logger.info("セール商品がないため、通知は送信されません")
        
        return True
    except LineBotApiError as e:
        logger.error(f"LINE API Error: {e}")
        return False
    except Exception as e:
        logger.error(f"LINE通知の送信中にエラーが発生: {str(e)}")
        return False

def next_schedule(context):
    # 現在の関数名を取得
    function_name = context.function_name

    # EventBridge クライアントの作成
    event_bridge = boto3.client('events')
    
    # Lambda クライアントの作成
    lambda_client = boto3.client('lambda')
    
    # まず、この関数に関連する既存のルールを検索して削除
    try:
        # ルールのプレフィックスを設定（関数名に基づく）
        rule_prefix = f"{function_name}-trigger-"
        
        # ルールを一覧取得
        response = event_bridge.list_rules(NamePrefix=rule_prefix)
        
        # 見つかったルールを削除
        for rule in response.get('Rules', []):
            rule_name = rule['Name']
            
            # まずルールのターゲットを削除
            try:
                targets = event_bridge.list_targets_by_rule(Rule=rule_name)
                if targets.get('Targets'):
                    target_ids = [t['Id'] for t in targets['Targets']]
                    event_bridge.remove_targets(Rule=rule_name, Ids=target_ids)
                    logger.info(f"ルール {rule_name} のターゲットを削除しました")
            except Exception as e:
                logger.error(f"ターゲット削除中にエラーが発生しました: {e}")
            
            # Lambda のパーミッションを削除
            try:
                lambda_client.remove_permission(
                    FunctionName=function_name,
                    StatementId=f'{rule_name}-permission'
                )
                logger.info(f"関数 {function_name} から {rule_name} のパーミッションを削除しました")
            except Exception as e:
                # パーミッションが見つからない場合などはエラーを無視
                logger.error(f"パーミッション削除中にエラーが発生しました: {e}")
            
            # ルールを削除
            event_bridge.delete_rule(Name=rule_name)
            logger.info(f"ルール {rule_name} を削除しました")
            
    except Exception as e:
        logger.error(f"既存ルール削除中にエラーが発生しました: {e}")
    
    # 次回実行時間をランダムに決定（600分～840分後）
    minutes_delay = random.randint(600, 840)
    # minutes_delay = random.randint(1, 2)  # テスト用（本番ではコメントアウト）
    next_run_time = datetime.now() + timedelta(minutes=minutes_delay)
    
    # cron式のための時間情報を取得
    hour = next_run_time.hour
    minute = next_run_time.minute
    day = next_run_time.day
    month = next_run_time.month
    year = next_run_time.year
    
    # EventBridgeのルール名（一意になるように日時を含める）
    rule_name = f"{function_name}-trigger-{year}{month:02d}{day:02d}{hour:02d}{minute:02d}"
    
    # cron式を作成（指定された時間に1回だけ実行）
    cron_expression = f"cron({minute} {hour} {day} {month} ? {year})"
    
    # 新しいEventBridgeルールを作成
    response = event_bridge.put_rule(
        Name=rule_name,
        ScheduleExpression=cron_expression,
        State='ENABLED',
        Description=f'Trigger for {function_name} at {next_run_time}'
    )
    
    # ルールのターゲットとして現在のLambda関数を設定
    event_bridge.put_targets(
        Rule=rule_name,
        Targets=[
            {
                'Id': '1',
                'Arn': f'arn:aws:lambda:{context.invoked_function_arn.split(":")[3]}:{context.invoked_function_arn.split(":")[4]}:function:{function_name}'
            }
        ]
    )
    
    # Lambda関数にEventBridgeからの呼び出し許可を追加
    lambda_client.add_permission(
        FunctionName=function_name,
        StatementId=f'{rule_name}-permission',
        Action='lambda:InvokeFunction',
        Principal='events.amazonaws.com',
        SourceArn=response['RuleArn']
    )
    
    logger.info(f"前回のルールを削除し、次回実行は {minutes_delay} 分後 ({next_run_time}) にスケジュールされました")

def lambda_handler(event, context):
    """Lambda用ハンドラー関数"""
    logger.info("Kindleセール監視を開始します")
    HEADERS["User-Agent"] = random.choice(USER_AGENTS)
    
    # DynamoDBクライアントの初期化
    dynamodb = boto3.resource('dynamodb')
    # テーブル名はイベントから取得するか、環境変数などから設定することも可能
    table_name = event.get('table_name', 'KindleItems')
    table = dynamodb.Table(table_name)

    try:
        # 重複実行チェック
        if is_already_running(table):
            logger.warning("スクレイパーが既に実行中のため、処理をスキップします")
            return {
                'statusCode': 409,  # Conflict
                'body': json.dumps({
                    'message': 'スクレイパーが既に実行中です。しばらく待ってから再度お試しください。'
                }, ensure_ascii=False)
            }
        
        # 実行中フラグを設定
        if not set_update_lock(table, context.function_name):
            logger.error("実行中フラグの設定に失敗しました")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'message': '実行中フラグの設定に失敗しました'
                }, ensure_ascii=False)
            }
        
        try:
            # テーブルからすべてのアイテムを取得
            items = scan_all_items(table)
            logger.info(f"取得したアイテム数: {len(items)}")
            
            # セール商品を検索（tableオブジェクトも渡す）
            sale_items = check_kindle_sales(items, table)
            
            # セール商品がある場合のみLINE通知を送信
            if sale_items:
                logger.info(f"{len(sale_items)}件のセール商品を検出し、通知します")
                send_line_message(sale_items)
            else:
                logger.info("通知すべきセール商品は検出されませんでした")

            # DBに保存
            update_item(table, items)

            # API経由での実行でない場合のみ次のスケジュールを設定
            if event.get('source') != 'api_trigger':
                next_schedule(context)
                logger.info("次回実行がスケジュールされました")
            else:
                logger.info("API経由での実行のため、次回スケジュールは設定しません")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f"{len(sale_items)}件のセール商品を検出し、通知しました",
                    'sale_items_count': len(sale_items),
                    'processed_items_count': len(items)
                }, ensure_ascii=False)
            }
            
        finally:
            # 実行中フラグをクリア（必ず実行）
            clear_update_lock(table)
            
    except Exception as e:
        logger.error(f"処理中にエラーが発生しました: {str(e)}")
        
        # エラーが発生した場合も実行中フラグをクリア
        try:
            clear_update_lock(table)
        except Exception as clear_error:
            logger.error(f"実行中フラグのクリアでもエラーが発生: {str(clear_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': f"エラーが発生しました: {str(e)}"
            }, ensure_ascii=False)
        }

# 互換性用のハンドラー
def handler(event, context):
    return lambda_handler(event, context)