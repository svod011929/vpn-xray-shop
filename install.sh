#!/bin/bash

# VPN X-Ray Shop - Интерактивная установка
# Для Ubuntu 22.04 LTS

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функции для вывода сообщений
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

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

prompt() {
    echo -e "${CYAN}$1${NC}"
}

# Функция для ввода с возможностью пропуска
read_input() {
    local prompt_text="$1"
    local default_value="$2"
    local allow_empty="$3"
    local is_password="$4"
    local result=""
    
    while true; do
        if [ "$is_password" = "true" ]; then
            prompt "$prompt_text"
            if [ -n "$default_value" ]; then
                echo -e "${YELLOW}(по умолчанию: скрыто)${NC}"
            fi
            if [ "$allow_empty" = "true" ]; then
                echo -e "${YELLOW}(нажмите Enter для пропуска)${NC}"
            fi
            read -s result
        else
            if [ -n "$default_value" ]; then
                prompt "$prompt_text (по умолчанию: $default_value):"
            else
                prompt "$prompt_text:"
            fi
            if [ "$allow_empty" = "true" ]; then
                echo -e "${YELLOW}(нажмите Enter для пропуска)${NC}"
            fi
            read result
        fi
        
        if [ -z "$result" ]; then
            if [ "$allow_empty" = "true" ]; then
                result="$default_value"
                break
            elif [ -n "$default_value" ]; then
                result="$default_value"
                break
            else
                warning "Это поле обязательно для заполнения!"
                continue
            fi
        fi
        break
    done
    
    echo "$result"
}

# Функция для подтверждения
confirm() {
    local prompt_text="$1"
    local default="$2"
    local result=""
    
    while true; do
        if [ "$default" = "y" ]; then
            prompt "$prompt_text (Y/n):"
        else
            prompt "$prompt_text (y/N):"
        fi
        read result
        
        if [ -z "$result" ]; then
            result="$default"
        fi
        
        case "$result" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) warning "Пожалуйста, введите y или n" ;;
        esac
    done
}

# Генерация случайного пароля
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Проверка, что скрипт запущен от root
if [[ $EUID -ne 0 ]]; then
   error "Этот скрипт должен быть запущен от root пользователя"
fi

# Приветствие
clear
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    VPN X-Ray Shop                            ║"
echo "║                 Интерактивная установка                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
info "Добро пожаловать в мастер установки VPN X-Ray Shop!"
info "Этот скрипт поможет вам настроить все компоненты системы."
echo ""

if ! confirm "Продолжить установку?" "y"; then
    info "Установка отменена."
    exit 0
fi

# Сбор конфигурации
echo ""
log "Сбор конфигурации..."
echo ""

# Основные настройки
prompt "=== ОСНОВНЫЕ НАСТРОЙКИ ==="
APP_URL=$(read_input "Введите URL вашего сайта" "https://kododrive.ru" false)
DOMAIN=$(echo "$APP_URL" | sed 's|https\?://||' | sed 's|/.*||')

# База данных
prompt "=== НАСТРОЙКИ БАЗЫ ДАННЫХ ==="
DB_PASSWORD=$(read_input "Пароль для базы данных PostgreSQL" "$(generate_password)" false true)

# Telegram Bot
prompt "=== НАСТРОЙКИ TELEGRAM БОТА ==="
TELEGRAM_BOT_TOKEN=$(read_input "Токен Telegram бота (получите у @BotFather)" "" false)
TELEGRAM_WEBHOOK_URL="$APP_URL/api/v1/webhook/telegram"

# Админ панель
prompt "=== НАСТРОЙКИ АДМИНИСТРАТОРА ==="
ADMIN_USERNAME=$(read_input "Логин администратора" "admin" false)
ADMIN_PASSWORD=$(read_input "Пароль администратора" "$(generate_password)" false true)

# Платежные системы
prompt "=== ПЛАТЕЖНЫЕ СИСТЕМЫ ==="
info "Следующие настройки можно пропустить и настроить позже"
echo ""

SETUP_PAYMENTS=false
if confirm "Настроить платежные системы сейчас?" "n"; then
    SETUP_PAYMENTS=true
    SEVER_PAY_API_KEY=$(read_input "API ключ Sever Pay" "" true)
    CRYPTO_PAY_TOKEN=$(read_input "Токен CryptoPay" "" true)
    XROCKET_PAY_KEY=$(read_input "Ключ XRocket Pay" "" true)
fi

# VPN панели
prompt "=== VPN ПАНЕЛИ ==="
info "Настройки VPN панелей можно добавить позже через админ-панель"
echo ""

SETUP_VPN_PANELS=false
if confirm "Настроить VPN панели сейчас?" "n"; then
    SETUP_VPN_PANELS=true
    THREE_XUI_PANELS=$(read_input "URL панелей 3x-ui (через запятую)" "" true)
    MARZBAN_PANELS=$(read_input "URL панелей Marzban (через запятую)" "" true)
fi

# SSL сертификат
prompt "=== SSL СЕРТИФИКАТ ==="
SETUP_SSL=false
SSL_EMAIL=""
if confirm "Получить SSL сертификат от Let's Encrypt?" "y"; then
    SETUP_SSL=true
    SSL_EMAIL=$(read_input "Email для уведомлений Let's Encrypt" "admin@$DOMAIN" false)
fi

# Подтверждение настроек
echo ""
prompt "=== ПОДТВЕРЖДЕНИЕ НАСТРОЕК ==="
echo -e "${CYAN}Домен:${NC} $DOMAIN"
echo -e "${CYAN}URL приложения:${NC} $APP_URL"
echo -e "${CYAN}Админ логин:${NC} $ADMIN_USERNAME"
echo -e "${CYAN}Telegram бот:${NC} ${TELEGRAM_BOT_TOKEN:0:10}..."
echo -e "${CYAN}SSL сертификат:${NC} $([ "$SETUP_SSL" = true ] && echo "Да" || echo "Нет")"
echo -e "${CYAN}Платежные системы:${NC} $([ "$SETUP_PAYMENTS" = true ] && echo "Настроены" || echo "Пропущены")"
echo -e "${CYAN}VPN панели:${NC} $([ "$SETUP_VPN_PANELS" = true ] && echo "Настроены" || echo "Пропущены")"
echo ""

if ! confirm "Все настройки верны? Начать установку?" "y"; then
    error "Установка отменена пользователем."
fi

# Начало установки
echo ""
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
    nano \
    jq

# Установка Docker и Docker Compose
log "Установка Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

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

# Создание директории проекта
log "Создание структуры проекта..."
PROJECT_DIR="/home/vpnbot/vpn-xray-shop"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Инициализация git репозитория
log "Инициализация Git репозитория..."
git init
git remote add origin https://github.com/svod011929/vpn-xray-shop.git || true

# Создание структуры проекта
mkdir -p {backend,frontend,nginx,scripts,docs,tests,certbot/conf,certbot/www}
mkdir -p backend/{app,alembic,tests}
mkdir -p backend/app/{api,core,db,models,schemas,services,bot}
mkdir -p backend/app/api/{v1,deps}
mkdir -p backend/app/api/v1/{endpoints,middleware}
mkdir -p frontend/{public,src}
mkdir -p frontend/src/{components,views,store,router,assets}

# Создание .env файла с собранными данными
log "Создание файла конфигурации..."
cat > .env << EOF
# Application
APP_NAME=VPN_XRAY_SHOP
APP_ENV=production
APP_DEBUG=false
APP_URL=$APP_URL
DOMAIN=$DOMAIN

# Database
DATABASE_URL=postgresql://vpnbot:$DB_PASSWORD@localhost:5432/vpnbot
REDIS_URL=redis://localhost:6379
DB_PASSWORD=$DB_PASSWORD

# Telegram Bot
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_WEBHOOK_URL=$TELEGRAM_WEBHOOK_URL

# Security
SECRET_KEY=$(openssl rand -hex 32)
JWT_SECRET_KEY=$(openssl rand -hex 32)
ACCESS_TOKEN_EXPIRE_MINUTES=30

# Admin
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_PASSWORD=$ADMIN_PASSWORD

# Payment Systems
EOF

if [ "$SETUP_PAYMENTS" = true ]; then
    cat >> .env << EOF
SEVER_PAY_API_KEY=$SEVER_PAY_API_KEY
CRYPTO_PAY_TOKEN=$CRYPTO_PAY_TOKEN
XROCKET_PAY_KEY=$XROCKET_PAY_KEY
EOF
else
    cat >> .env << EOF
SEVER_PAY_API_KEY=
CRYPTO_PAY_TOKEN=
XROCKET_PAY_KEY=
EOF
fi

if [ "$SETUP_VPN_PANELS" = true ]; then
    cat >> .env << EOF

# VPN Panels
THREE_XUI_PANELS=$THREE_XUI_PANELS
MARZBAN_PANELS=$MARZBAN_PANELS
EOF
else
    cat >> .env << EOF

# VPN Panels
THREE_XUI_PANELS=
MARZBAN_PANELS=
EOF
fi

# Создание основных файлов проекта
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

# Dockerfile для backend
cat > backend/Dockerfile << 'EOF'
FROM python:3.10-slim

WORKDIR /app

# Установка системных зависимостей
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Копирование и установка Python зависимостей
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Копирование кода приложения
COPY . .

# Создание пользователя для безопасности
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
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
from pydantic_settings import
