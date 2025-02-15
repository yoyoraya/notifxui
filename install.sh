#!/bin/bash

# تنظیمات اولیه
PROJECT_DIR="notifx-ui"
ENV_FILE=".env"

# ایجاد دایرکتوری پروژه
echo "Creating project directory: $PROJECT_DIR..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# به‌روزرسانی سیستم و نصب پیش‌نیازها
echo "Updating system and installing prerequisites..."
sudo apt update && sudo apt upgrade -y
sudo apt install python3 python3-pip git -y

# نصب کتابخانه‌های مورد نیاز
echo "Installing required Python libraries..."
pip3 install python-telegram-bot requests python-dotenv

# دریافت توکن ربات تلگرام از کاربر
read -p "Enter your Telegram Bot Token: " TELEGRAM_BOT_TOKEN

# ایجاد فایل .env
echo "Creating .env file..."
cat <<EOL > $ENV_FILE
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
ENV=production
EOL

# ایجاد فایل bot.py با کد پایتون
echo "Creating bot.py..."
cat <<'EOF' > bot.py
import logging
import sqlite3
import os
import requests
import json
import time
from typing import List, Tuple, Dict, Any, Generator
from urllib.parse import urlparse
from datetime import datetime
from dotenv import load_dotenv
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, ContextTypes, CallbackQueryHandler

# تنظیمات پیشرفته لاگینگ
logging.basicConfig(
    level=logging.WARNING if os.getenv('ENV') == 'production' else logging.INFO,
    format='[%(levelname)s] %(asctime)s - %(name)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

load_dotenv()

class DatabaseManager:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path, check_same_thread=False)
        self._init_db()

    def _init_db(self):
        with self.conn:
            self.conn.execute('''
                CREATE TABLE IF NOT EXISTS servers (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    url TEXT NOT NULL UNIQUE,
                    username TEXT NOT NULL,
                    password TEXT NOT NULL,
                    panel_type TEXT NOT NULL DEFAULT '3x-ui',
                    last_connection DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            ''')

    def _execute(self, query: str, params: tuple = ()):
        with self.conn:
            return self.conn.execute(query, params)

    def add_server(self, url: str, username: str, password: str, panel_type: str = "3x-ui") -> bool:
        try:
            self._execute('''
                INSERT OR REPLACE INTO servers (url, username, password, panel_type)
                VALUES (?, ?, ?, ?)
            ''', (url, username, password, panel_type))
            return True
        except sqlite3.Error as e:
            logger.error(f"Database error: {e}")
            return False

    def delete_server(self, url: str) -> bool:
        try:
            cursor = self._execute('DELETE FROM servers WHERE url = ?', (url,))
            return cursor.rowcount > 0
        except sqlite3.Error as e:
            logger.error(f"Database error: {e}")
            return False

    def get_all_servers(self) -> Generator[Tuple[str, str, str, str], None, None]:
        cursor = self._execute('SELECT url, username, password, panel_type FROM servers ORDER BY last_connection DESC')
        while (row := cursor.fetchone()) is not None:
            yield row

class XUIClient:
    _session_cache = {}

    def __new__(cls, base_url: str, username: str, password: str):
        key = (base_url, username, password)
        if key not in cls._session_cache:
            instance = super().__new__(cls)
            instance.__init__(base_url, username, password)
            cls._session_cache[key] = instance
        return cls._session_cache[key]

    def __init__(self, base_url: str, username: str, password: str):
        self.base_url = base_url
        self.username = username
        self.password = password
        self.session = requests.Session()
        self.is_logged_in = False
        self.token = None

    async def login(self) -> bool:
        if self.is_logged_in:
            return True
            
        try:
            response = self.session.post(
                f"{self.base_url}/login",
                data={'username': self.username, 'password': self.password},
                headers={'Accept': 'application/json'},
                timeout=5
            )
            if response.status_code == 200:
                self.is_logged_in = True
                # اگر پنل alireza0 از توکن استفاده می‌کند، آن را ذخیره کنید
                self.token = response.json().get('token')
                logger.info(f"Logged in successfully to {self.base_url}")
                return True
            else:
                logger.error(f"Login failed with status code: {response.status_code}")
                return False
        except requests.RequestException as e:
            logger.error(f"Login error: {e}")
            return False

    async def get_inbounds(self, panel_type: str) -> Any:
        if not await self.login():
            logger.error("Cannot fetch inbounds: Login failed")
            return None

        try:
            endpoint = {
                "alireza0": "/xui/API/inbounds/",  # Endpoint برای پنل alireza0
                "3x-ui": "/panel/api/inbounds/list"
            }.get(panel_type, "/panel/api/inbounds/list")

            headers = {'Accept': 'application/json'}
            if panel_type == "alireza0" and self.token:
                headers['Authorization'] = f"Bearer {self.token}"

            logger.info(f"Fetching inbounds from {self.base_url}{endpoint}")
            response = self.session.get(
                f"{self.base_url}{endpoint}",
                headers=headers,
                timeout=10
            )
            if response.status_code == 200:
                logger.info(f"Successfully fetched inbounds from {self.base_url}")
                return response.json()
            else:
                logger.error(f"Failed to fetch inbounds: Status code {response.status_code}, Response: {response.text}")
                return None
        except Exception as e:
            logger.error(f"Data fetch error: {e}")
            return None

def process_notif_data(data: dict, panel_type: str) -> dict:
    current_time = int(time.time() * 1000)
    categories = {
        'near_expiry': [],
        'low_traffic': [],
        'over_traffic': [],
        'expired': []
    }

    # اگر پنل alireza0 ساختار JSON متفاوتی دارد، این بخش را تغییر دهید
    inbounds = data.get('obj', [])
    for inbound in inbounds:
        try:
            settings = json.loads(inbound.get('settings', '{}'))
            clients = {c['email']: c for c in settings.get('clients', [])}

            for stat in inbound.get('clientStats', []):
                client = clients.get(stat['email'], {})
                if not client.get('enable', False):
                    continue

                expiry = stat['expiryTime']
                if expiry < 0 or (expiry == 0 and stat['total'] == 0):
                    continue

                remaining = stat['total'] - (stat['up'] + stat['down'])
                
                if expiry > 0:
                    if expiry < current_time:
                        categories['expired'].append(stat)
                        continue
                    if (expiry - current_time) < 25 * 3600 * 1000:
                        categories['near_expiry'].append(stat)
                        continue
                
                if remaining <= 0:
                    categories['over_traffic'].append(stat)
                elif 0.01 <= (remaining / (1024**3)) <= 1:
                    categories['low_traffic'].append(stat)

        except Exception as e:
            logger.error(f"Processing error: {e}")

    return categories

class TelegramBot:
    def __init__(self, token: str, db_manager: DatabaseManager):
        self.token = token
        self.db = db_manager

    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        help_text = """
        🤖 X-UI Management Bot (Optimized)

        Commands:
        /connect <address:port> <username> <password> <panel_type> - Add server
        /delete <address:port> - Remove server
        /listservers - List servers (paginated)
        /notif - Check users status
        /help - Show help
        """
        await update.message.reply_text(help_text)

    async def connect(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        args = context.args
        if len(args) != 4:
            await update.message.reply_text("⚠️ Invalid format!\nExample: /connect example.com:2053 admin password123 3x-ui")
            return

        url = self.normalize_url(args[0])
        panel_type = args[3].lower()
        if panel_type not in ["alireza0", "3x-ui"]:
            await update.message.reply_text("⚠️ Invalid panel type! Use 'alireza0' or '3x-ui'")
            return

        if self.db.add_server(url, args[1], args[2], panel_type):
            await update.message.reply_text("✅ Server added successfully!")
        else:
            await update.message.reply_text("❌ Failed to add server!")

    async def delete(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not context.args:
            await update.message.reply_text("⚠️ Please enter server address!\nExample: /delete example.com:2053")
            return

        url = self.normalize_url(' '.join(context.args))
        if self.db.delete_server(url):
            await update.message.reply_text("🗑️ Server deleted!")
        else:
            await update.message.reply_text("ℹ️ Server not found!")

    async def list_servers(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        servers = list(self.db.get_all_servers())
        chunk_size = 15
        for i in range(0, len(servers), chunk_size):
            chunk = servers[i:i+chunk_size]
            response = "\n".join(
                f"{idx+1}. {urlparse(url).netloc} ({panel_type})" 
                for idx, (url, _, _, panel_type) in enumerate(chunk, start=i)
            )
            await update.message.reply_text(response or "ℹ️ No servers registered")

    async def notif(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        servers = list(self.db.get_all_servers())
        if not servers:
            await update.message.reply_text("ℹ️ No servers registered!")
            return

        keyboard = [
            [InlineKeyboardButton(
                f"🌐 {urlparse(url).netloc} ({panel_type})", 
                callback_data=f"server_{urlparse(url).netloc}"
            )] for url, _, _, panel_type in servers
        ]
        
        reply_markup = InlineKeyboardMarkup(keyboard)
        await update.message.reply_text(
            "Available servers:",
            reply_markup=reply_markup
        )

    async def button_handler(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        query = update.callback_query
        await query.answer()
        data = query.data

        if data.startswith("server_"):
            domain = data.split("_", 1)[1]
            await self.show_categories(query, domain)
        elif data == "back_main":
            await self.notif(query, context)

    async def show_categories(self, query, domain):
        server = next((s for s in self.db.get_all_servers() if domain in s[0]), None)
        if not server:
            await query.edit_message_text("⛔ Server not found")
            return

        url, username, password, panel_type = server
        client = XUIClient(url, username, password)
        data = await client.get_inbounds(panel_type)
        
        if not data:
            await query.edit_message_text("❌ Error fetching data")
            return

        categories = process_notif_data(data, panel_type)
        message = [f"📡 **Server:** `{domain}`\n"]
        
        category_map = {
            'near_expiry': ('⏳', 'Near Expiry'),
            'low_traffic': ('🪫', 'Low Traffic'),
            'over_traffic': ('🔴', 'Over Traffic'),
            'expired': ('⛔️', 'Expired')
        }

        for cat, (emoji, title) in category_map.items():
            if users := categories[cat]:
                message.append(f"\n{emoji*3} **{title}** {emoji*3}\n")
                message.extend(f"`{user['email']}`\n" for user in users)

        keyboard = [[InlineKeyboardButton("🔙 Back to Servers", callback_data="back_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await query.edit_message_text(
            "".join(message).strip(),
            reply_markup=reply_markup,
            parse_mode="Markdown"
        )

    def normalize_url(self, address: str) -> str:
        return f"http://{address}" if not address.startswith(('http://', 'https://')) else address

    def run(self):
        app = (
            Application.builder()
            .token(self.token)
            .concurrent_updates(False)
            .http_version("1.1")
            .get_updates_http_version("1.1")
            .build()
        )
        handlers = [
            CommandHandler("start", self.start),
            CommandHandler("connect", self.connect),
            CommandHandler("delete", self.delete),
            CommandHandler("listservers", self.list_servers),
            CommandHandler("notif", self.notif),
            CommandHandler("help", self.start),
            CallbackQueryHandler(self.button_handler)
        ]
        for handler in handlers:
            app.add_handler(handler)
        app.run_polling(drop_pending_updates=True)

if __name__ == '__main__':
    db = DatabaseManager("servers.db")
    bot = TelegramBot(os.getenv("TELEGRAM_BOT_TOKEN"), db)
    bot.run()
EOF

# اجرای ربات
echo "Starting the bot..."
python3 bot.py
