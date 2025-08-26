#!/bin/bash

# VPN X-Ray Shop - Автоматическая установка
# Для Ubuntu 22.04 LTS

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка, что скрипт запущен от root
if [[ $EUID -ne 0 ]]; then
   error "Этот скрипт должен быть запущен от root пользователя"
fi

log "Начало установки VPN X-Ray Shop..."

# Обновление системы
log "Обновление системы..."
apt update && apt upgrade -y

# Установка базовых зависимостей
log "Установка базовых зависимостей..."
apt install -y \
    curl \
    wget \
    git \
    build-essential \
    python3.10 \
    python3.10-venv \
    python3-pip \
    postgresql \
    postgresql-contrib \
    redis-server \
    nginx \
    certbot \
    python3-certbot-nginx \
    supervisor \
    ufw \
    htop \
    nano

# Установка Docker и Docker Compose
log "Установка Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Установка Docker Compose
log "Установка Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Установка Node.js для фронтенда
log "Установка Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Создание пользователя для приложения
log "Создание пользователя приложения..."
useradd -m -s /bin/bash vpnbot || warning "Пользователь vpnbot уже существует"

# Клонирование репозитория
log "Клонирование репозитория..."
cd /home/vpnbot
if [ -d "vpn-xray-shop" ]; then
    warning "Директория уже существует, обновляем..."
    cd vpn-xray-shop
    git pull
else
    git clone https://github.com/svod011929/vpn-xray-shop.git
    cd vpn-xray-shop
fi

# Создание структуры проекта
log "Создание структуры проекта..."
mkdir -p {backend,frontend,nginx,scripts,docs,tests}
mkdir -p backend/{app,alembic,tests}
mkdir -p backend/app/{api,core,db,models,schemas,services,bot}
mkdir -p frontend/{public,src}
mkdir -p frontend/src/{components,views,store,router,assets}

# Создание .env файла
log "Создание файла окружения..."
cat > .env << 'EOF'
# Application
APP_NAME=VPN_XRAY_SHOP
APP_ENV=production
APP_DEBUG=false
APP_URL=https://kododrive.ru

# Database
DATABASE_URL=postgresql://vpnbot:CHANGE_ME_DB_PASSWORD@localhost:5432/vpnbot
REDIS_URL=redis://localhost:6379

# Telegram Bot
TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
TELEGRAM_WEBHOOK_URL=https://kododrive.ru/api/v1/webhook/telegram

# Security
SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)

# Payment Systems
SEVER_PAY_API_KEY=YOUR_SEVER_PAY_KEY
CRYPTO_PAY_TOKEN=YOUR_CRYPTO_PAY_TOKEN
XROCKET_PAY_KEY=YOUR_XROCKET_KEY

# VPN Panels
THREE_XUI_PANELS=
MARZBAN_PANELS=

# Admin
ADMIN_USERNAME=admin
ADMIN_PASSWORD=CHANGE_ME_ADMIN_PASSWORD
EOF

# Создание основных файлов Python
log "Создание файлов приложения..."

# requirements.txt
cat > backend/requirements.txt << 'EOF'
# Core
fastapi==0.104.1
uvicorn[standard]==0.24.0
python-dotenv==1.0.0
pydantic==2.5.0
pydantic-settings==2.1.0

# Database
sqlalchemy==2.0.23
alembic==1.12.1
asyncpg==0.29.0
redis==5.0.1

# Telegram Bot
aiogram==3.2.0
aiohttp==3.9.1

# Authentication
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.6

# Payment Systems
httpx==0.25.2

# Utils
celery==5.3.4
flower==2.0.1
python-dateutil==2.8.2
pytz==2023.3

# Testing
pytest==7.4.3
pytest-asyncio==0.21.1
pytest-cov==4.1.0

# Monitoring
prometheus-client==0.19.0
sentry-sdk==1.38.0
EOF

# main.py
cat > backend/main.py << 'EOF'
import uvicorn
from app.core.config import settings
from app.api.app import create_app

app = create_app()

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.APP_DEBUG
    )
EOF

# app/core/config.py
cat > backend/app/core/config.py << 'EOF'
from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # Application
    APP_NAME: str = "VPN X-Ray Shop"
    APP_ENV: str = "development"
    APP_DEBUG: bool = True
    APP_URL: str
    
    # Database
    DATABASE_URL: str
    REDIS_URL: str
    
    # Telegram
    TELEGRAM_BOT_TOKEN: str
    TELEGRAM_WEBHOOK_URL: str
    
    # Security
    SECRET_KEY: str
    JWT_SECRET_KEY: str
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    
    # Payment Systems
    SEVER_PAY_API_KEY: Optional[str] = None
    CRYPTO_PAY_TOKEN: Optional[str] = None
    XROCKET_PAY_KEY: Optional[str] = None
    
    # VPN Panels
    THREE_XUI_PANELS: Optional[str] = None
    MARZBAN_PANELS: Optional[str] = None
    
    # Admin
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str
    
    class Config:
        env_file = ".env"

settings = Settings()
EOF

# app/api/app.py
cat > backend/app/api/app.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.v1.router import api_router

def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.APP_NAME,
        openapi_url="/api/openapi.json",
        docs_url="/api/docs",
        redoc_url="/api/redoc"
    )
    
    # CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # Routers
    app.include_router(api_router, prefix="/api/v1")
    
    @app.get("/health")
    async def health_check():
        return {"status": "healthy"}
    
    return app
EOF

# Docker Compose для продакшена
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  backend:
    build: ./backend
    container_name: vpn_backend
    restart: always
    env_file: .env
    ports:
      - "8000:8000"
    depends_on:
      - postgres
      - redis
    volumes:
      - ./backend:/app
    command: uvicorn main:app --host 0.0.0.0 --port 8000

  bot:
    build: ./backend
    container_name: vpn_bot
    restart: always
    env_file: .env
    depends_on:
      - backend
      - postgres
      - redis
    volumes:
      - ./backend:/app
    command: python -m app.bot.main

  postgres:
    image: postgres:15-alpine
    container_name: vpn_postgres
    restart: always
    environment:
      POSTGRES_USER: vpnbot
      POSTGRES_PASSWORD: ${DB_PASSWORD:-changeme}
      POSTGRES_DB: vpnbot
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    container_name: vpn_redis
    restart: always
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"

  nginx:
    image: nginx:alpine
    container_name: vpn_nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./frontend/dist:/var/www/html
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    depends_on:
      - backend

  certbot:
    image: certbot/certbot
    container_name: vpn_certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"

volumes:
  postgres_data:
  redis_data:
EOF

# Nginx конфигурация
cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    upstream backend {
        server backend:8000;
    }

    server {
        listen 80;
        server_name kododrive.ru www.kododrive.ru;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 301 https://$server_name$request_uri;
        }
    }

    server {
        listen 443 ssl;
        server_name kododrive.ru www.kododrive.ru;

        ssl_certificate /etc/letsencrypt/live/kododrive.ru/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/kododrive.ru/privkey.pem;

        # Лендинг
        location / {
            root /var/www/html;
            try_files $uri $uri/ /index.html;
        }

        # Админ панель
        location /admin {
            root /var/www/html;
            try_files $uri $uri/ /admin/index.html;
        }

        # API
        location /api {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # WebSocket для бота
        location /ws {
            proxy_pass http://backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF

# Создание базы данных
log "Настройка PostgreSQL..."
sudo -u postgres psql << EOF
CREATE USER vpnbot WITH PASSWORD 'CHANGE_ME_DB_PASSWORD';
CREATE DATABASE vpnbot OWNER vpnbot;
GRANT ALL PRIVILEGES ON DATABASE vpnbot TO vpnbot;
EOF

# Настройка firewall
log "Настройка firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Получение SSL сертификата
log "Получение SSL сертификата..."
certbot certonly --nginx -d kododrive.ru -d www.kododrive.ru --non-interactive --agree-tos -m admin@kododrive.ru

# Создание скрипта для обновления
cat > update.sh << 'EOF'
#!/bin/bash
cd /home/vpnbot/vpn-xray-shop
git pull
docker-compose down
docker-compose build
docker-compose up -d
EOF
chmod +x update.sh

# Финальные инструкции
log "Установка завершена!"
echo ""
echo "========================================"
echo "ВАЖНО! Выполните следующие действия:"
echo "========================================"
echo "1. Отредактируйте файл .env и установите:"
echo "   - TELEGRAM_BOT_TOKEN"
echo "   - Пароли для базы данных и админа"
echo "   - Ключи платежных систем"
echo ""
echo "2. Запустите приложение:"
echo "   cd /home/vpnbot/vpn-xray-shop"
echo "   docker-compose up -d"
echo ""
echo "3. Примените миграции базы данных:"
echo "   docker-compose exec backend alembic upgrade head"
echo ""
echo "4. Проверьте статус:"
echo "   docker-compose ps"
echo ""
echo "Админ панель: https://kododrive.ru/admin"
echo "API документация: https://kododrive.ru/api/docs"
echo "========================================"
