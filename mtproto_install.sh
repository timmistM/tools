#!/bin/bash

# ============================================
# MTProto Proxy — автоматическая установка
# Для Ubuntu/Debian VPS
# ============================================

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   MTProto Proxy — Автоустановка          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ---- 1. Проверка root ----
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Запусти скрипт от root: sudo bash mtproto_install.sh${NC}"
  exit 1
fi

# ---- 2. Проверка и установка Docker ----
echo -e "${YELLOW}[1/5] Проверяю Docker...${NC}"
if command -v docker &> /dev/null; then
  echo -e "${GREEN}  ✓ Docker уже установлен: $(docker --version)${NC}"
else
  echo -e "${YELLOW}  → Docker не найден, устанавливаю...${NC}"
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  echo -e "${GREEN}  ✓ Docker установлен${NC}"
fi

# Проверяю xxd (нужен для генерации секрета)
if ! command -v xxd &> /dev/null; then
  echo -e "${YELLOW}  → Устанавливаю xxd...${NC}"
  apt-get install -y -qq xxd 2>/dev/null || apt-get install -y -qq vim-common 2>/dev/null || true
fi

# ---- 3. Выбор порта ----
echo -e "${YELLOW}[2/5] Ищу свободный порт...${NC}"

# Предпочтительные порты (выглядят как HTTPS)
PREFERRED_PORTS=(443 8443 2083 2096 8080)
CHOSEN_PORT=""

for port in "${PREFERRED_PORTS[@]}"; do
  if ! ss -tlnp | grep -q ":${port} "; then
    CHOSEN_PORT=$port
    break
  fi
done

if [ -z "$CHOSEN_PORT" ]; then
  # Если все предпочтительные заняты — берём случайный
  CHOSEN_PORT=$(shuf -i 10000-60000 -n 1)
  while ss -tlnp | grep -q ":${CHOSEN_PORT} "; do
    CHOSEN_PORT=$(shuf -i 10000-60000 -n 1)
  done
fi

echo -e "${GREEN}  ✓ Выбран порт: ${CHOSEN_PORT}${NC}"

# Показываю занятые порты для информации
echo -e "${CYAN}  Занятые порты на сервере:${NC}"
ss -tlnp | grep LISTEN | awk '{print "    " $4}' | sed 's/.*:/    порт /'

# ---- 4. Генерация секрета ----
echo -e "${YELLOW}[3/5] Генерирую секрет...${NC}"
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
echo -e "${GREEN}  ✓ Секрет сгенерирован${NC}"

# ---- 5. Удаление старого контейнера если есть ----
if docker ps -a --format '{{.Names}}' | grep -q "^mtproto-proxy$"; then
  echo -e "${YELLOW}  → Удаляю старый контейнер mtproto-proxy...${NC}"
  docker stop mtproto-proxy 2>/dev/null || true
  docker rm mtproto-proxy 2>/dev/null || true
fi

# ---- 6. Запуск контейнера ----
echo -e "${YELLOW}[4/5] Запускаю MTProto Proxy...${NC}"

TLS_DOMAIN="www.google.com"

docker run -d \
  --name mtproto-proxy \
  --restart=always \
  -p ${CHOSEN_PORT}:${CHOSEN_PORT} \
  -v mtproto-data:/data \
  seriyps/mtproto_proxy \
  -p ${CHOSEN_PORT} \
  -s ${SECRET} \
  -t 1 \
  --tls-domain ${TLS_DOMAIN}

# Ждём запуска
echo -e "${YELLOW}  → Жду запуска контейнера...${NC}"
sleep 5

# Проверяю что контейнер работает
if docker ps --format '{{.Names}}' | grep -q "^mtproto-proxy$"; then
  echo -e "${GREEN}  ✓ Контейнер запущен${NC}"
else
  echo -e "${RED}[!] Контейнер не запустился. Логи:${NC}"
  docker logs mtproto-proxy
  exit 1
fi

# ---- 7. Определение внешнего IP ----
echo -e "${YELLOW}[5/5] Получаю внешний IP...${NC}"
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 api.ipify.org 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null)

if [ -z "$SERVER_IP" ]; then
  echo -e "${RED}  [!] Не удалось определить IP автоматически${NC}"
  echo -e "${YELLOW}  Введи IP сервера вручную:${NC}"
  read -r SERVER_IP
fi

# ---- 8. Формирование ссылки ----
# Fake-TLS секрет: ee + hex(secret) + hex(domain)
TLS_DOMAIN_HEX=$(echo -n ${TLS_DOMAIN} | xxd -ps)
FULL_SECRET="ee${SECRET}${TLS_DOMAIN_HEX}"

TG_LINK="https://t.me/proxy?server=${SERVER_IP}&port=${CHOSEN_PORT}&secret=${FULL_SECRET}"

# ---- 9. Настройка firewall ----
if command -v ufw &> /dev/null; then
  ufw allow ${CHOSEN_PORT}/tcp 2>/dev/null || true
  echo -e "${GREEN}  ✓ Порт ${CHOSEN_PORT} открыт в UFW${NC}"
fi

# ---- РЕЗУЛЬТАТ ----
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        ✅ MTProto Proxy установлен!       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}  Сервер:  ${SERVER_IP}${NC}"
echo -e "${GREEN}  Порт:    ${CHOSEN_PORT}${NC}"
echo -e "${GREEN}  Домен:   ${TLS_DOMAIN} (fake-TLS)${NC}"
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${YELLOW}  📋 ССЫЛКА ДЛЯ TELEGRAM (скопируй):${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}${TG_LINK}${NC}"
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}  Команды управления:${NC}"
echo -e "  Логи:        docker logs mtproto-proxy"
echo -e "  Перезапуск:  docker restart mtproto-proxy"
echo -e "  Остановка:   docker stop mtproto-proxy"
echo -e "  Удаление:    docker stop mtproto-proxy && docker rm mtproto-proxy"
echo ""
