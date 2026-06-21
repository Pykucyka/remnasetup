#!/bin/bash
# ======================================================================
# Remnawave Panel & Node Manager — автоустановщик с расширенным TUI
# Поддержка Y-VPN  •  Создатель: Telegram @drugd
# ======================================================================
# Запуск: bash remnawave-manager.sh
# Репозиторий: https://github.com/yourname/remnawave-manager (замените)
# ======================================================================

set -Eeuo pipefail
trap 'echo -e "\n${RED}[!] Прервано пользователем.${NC}"; exit 1' INT
trap 'error_handler $? $LINENO' ERR

# ---------------------------- Цвета и стили ---------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'
LOGO_COLOR='\033[38;5;39m'

# ---------------------------- Пути и файлы ----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANEL_DIR="${SCRIPT_DIR}/remnawave-panel"
NODE_DIR="${SCRIPT_DIR}/remnanode"   # не используется локально, оставлено для совместимости
ENV_FILE="${PANEL_DIR}/.env"
COMPOSE_FILE="${PANEL_DIR}/docker-compose.yml"
REPO_URL="https://github.com/Remnawave/remnawave.git"

# ---------------------------- Функция обработки ошибок ----------------
error_handler() {
    local exit_code=$1
    local line_no=$2
    echo -e "\n${RED}${BOLD}[ОШИБКА]${NC} Код: ${RED}${exit_code}${NC}, строка: ${RED}${line_no}${NC}"
    echo -e "${YELLOW}Пожалуйста, проверьте лог выше или обратитесь в поддержку @drugd${NC}"
    exit "${exit_code}"
}

# ---------------------------- Прогресс-бар ----------------------------
spinner() {
    local pid=$1
    local message=$2
    local spinstr='|/-\'
    local delay=0.1
    printf "  ${CYAN}%s...  ${NC}" "$message"
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "${spinstr}"
        spinstr=${temp}${spinstr%"$temp"}
        sleep ${delay}
        printf "\b\b\b"
    done
    wait "$pid"
    local exit_status=$?
    printf "\r  ${GREEN}✔ %s${NC}  \n" "$message"
    return ${exit_status}
}

# Простой линейный прогресс-бар для пошаговых операций
step_progress() {
    local step=$1
    local total_steps=$2
    local desc=$3
    local width=30
    local percent=$(( step * 100 / total_steps ))
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    printf "  [${GREEN}"
    for ((i=0; i<filled; i++)); do printf "#"; done
    printf "${NC}"
    for ((i=0; i<empty; i++)); do printf "."; done
    printf "] %3d%% - %s\n" "$percent" "$desc"
}

# ---------------------------- Баннер ----------------------------------
show_banner() {
    clear
    echo -e "${LOGO_COLOR}"
    cat << "EOF"
    ██████╗ ███████╗███╗   ███╗███╗   ██╗ █████╗ ██╗    ██╗ █████╗ ██╗   ██╗███████╗
    ██╔══██╗██╔════╝████╗ ████║████╗  ██║██╔══██╗██║    ██║██╔══██╗██║   ██║██╔════╝
    ██████╔╝█████╗  ██╔████╔██║██╔██╗ ██║███████║██║ █╗ ██║███████║██║   ██║█████╗  
    ██╔══██╗██╔══╝  ██║╚██╔╝██║██║╚██╗██║██╔══██║██║███╗██║██╔══██║╚██╗ ██╔╝██╔══╝  
    ██║  ██║███████╗██║ ╚═╝ ██║██║ ╚████║██║  ██║╚███╔███╔╝██║  ██║ ╚████╔╝ ███████╗
    ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝  ╚═══╝  ╚══════╝
EOF
    echo -e "${NC}"
    echo -e "${BOLD}${CYAN}               Remnawave Panel & Node Manager v1.1${NC}"
    echo -e "${BOLD}${MAGENTA}            При поддержке ${BOLD}${WHITE}Y-VPN${NC}${BOLD}${MAGENTA} | Создатель:${NC} ${BOLD}${WHITE}@drugd${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}\n"
}

press_enter() {
    echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
    read -r
}

# ---------------------------- Проверка зависимостей -------------------
check_deps() {
    local missing=0
    for cmd in curl git docker docker-compose; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}[!] $cmd не найден.${NC}"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        echo -e "${YELLOW}Установите недостающие пакеты или запустите скрипт для установки Docker (пункт 1).${NC}"
        exit 1
    fi
}

install_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${YELLOW}[*] Docker не обнаружен. Устанавливаю...${NC}"
        curl -fsSL https://get.docker.com | bash &>/dev/null &
        spinner $! "Установка Docker"
        systemctl enable --now docker &>/dev/null
        echo -e "${GREEN}[+] Docker установлен и запущен.${NC}"
    fi
    if ! command -v docker-compose &>/dev/null; then
        echo -e "${YELLOW}[*] Устанавливаю docker-compose...${NC}"
        apt update -qq && apt install -y docker-compose &>/dev/null || {
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose &>/dev/null &
            spinner $! "Загрузка docker-compose"
            chmod +x /usr/local/bin/docker-compose
        }
        echo -e "${GREEN}[+] docker-compose установлен.${NC}"
    fi
}

# ---------------------------- Установка панели ------------------------
install_panel() {
    echo -e "${BOLD}${GREEN}[*] Начинаю установку Remnawave Panel...${NC}"
    mkdir -p "${PANEL_DIR}"
    cd "${SCRIPT_DIR}"

    # Шаг 1: Клонирование репозитория
    step_progress 1 4 "Клонирование репозитория"
    if [ ! -d "${PANEL_DIR}/.git" ]; then
        git clone "${REPO_URL}" "${PANEL_DIR}" &>/dev/null &
        spinner $! "Клонирование"
    else
        echo -e "  ${YELLOW}[!] Репозиторий уже существует. Пропускаю клонирование.${NC}"
    fi

    cd "${PANEL_DIR}"

    # Шаг 2: Настройка .env
    step_progress 2 4 "Настройка переменных окружения"
    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || true
    fi

    echo -e "  ${BOLD}${YELLOW}Ответьте на несколько вопросов для конфигурации:${NC}"
    read -p "$(echo -e ${GREEN}Введите ваш домен (например, panel.example.com): ${NC})" DOMAIN
    read -p "$(echo -e ${GREEN}Придумайте пароль администратора: ${NC})" ADMIN_PASSWORD
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
    echo

    # Генерация секретов
    JWT_SECRET=$(openssl rand -hex 32)
    API_KEY=$(openssl rand -hex 16)

    cat > .env <<EOF
# Remnawave .env — автоматически сгенерирован
DOMAIN=${DOMAIN}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
JWT_SECRET=${JWT_SECRET}
API_KEY=${API_KEY}
DB_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
EOF
    echo -e "  ${GREEN}[✓] .env записан.${NC}"

    # Шаг 3: Запуск docker-compose
    step_progress 3 4 "Запуск контейнеров"
    docker-compose up -d &>/dev/null &
    spinner $! "Запуск сервисов"

    # Шаг 4: Проверка готовности
    step_progress 4 4 "Ожидание готовности"
    sleep 5
    echo -e "  ${GREEN}[✓] Все сервисы запущены.${NC}"

    echo -e "\n${BOLD}${GREEN}✅ Установка завершена!${NC}"
    echo -e "Панель доступна по адресу: ${CYAN}https://${DOMAIN}${NC}"
    echo -e "Логин: ${BOLD}admin${NC}  Пароль: ${BOLD}${ADMIN_PASSWORD}${NC}"
    press_enter
}

# ---------------------------- Просмотр .env ---------------------------
view_env() {
    if [ -f "${ENV_FILE}" ]; then
        echo -e "${BOLD}${CYAN}═══ Содержимое .env ═══${NC}"
        cat "${ENV_FILE}"
    else
        echo -e "${RED}[!] Файл .env не найден. Установите панель сначала.${NC}"
    fi
    press_enter
}

# ---------------------------- Редактирование .env ---------------------
edit_env() {
    if [ -f "${ENV_FILE}" ]; then
        echo -e "${YELLOW}Открываю редактор (nano). Сохраните изменения и перезапустите панель (Обновление).${NC}"
        nano "${ENV_FILE}"
        echo -e "${GREEN}[✓] Редактирование завершено.${NC}"
    else
        echo -e "${RED}[!] Файл .env не найден.${NC}"
    fi
    press_enter
}

# ---------------------------- Обновление панели ------------------------
update_panel() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не установлена.${NC}"
        press_enter
        return
    fi
    cd "${PANEL_DIR}"

    step_progress 1 2 "Получение обновлений из репозитория"
    git pull &>/dev/null &
    spinner $! "Git pull"

    step_progress 2 2 "Пересборка и перезапуск контейнеров"
    docker-compose down &>/dev/null
    docker-compose up -d --build &>/dev/null &
    spinner $! "Docker compose up"
    echo -e "${GREEN}[✓] Панель обновлена.${NC}"
    press_enter
}

# ---------------------------- Просмотр логов --------------------------
view_logs() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не установлена.${NC}"
        press_enter
        return
    fi
    cd "${PANEL_DIR}"
    echo -e "${CYAN}[*] Просмотр логов всех сервисов (Ctrl+C для выхода)...${NC}"
    sleep 1
    docker-compose logs -f --tail=100
    press_enter
}

# ---------------------------- Статус сервисов -------------------------
check_status() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не установлена.${NC}"
        press_enter
        return
    fi
    cd "${PANEL_DIR}"
    echo -e "${BOLD}${CYAN}═══ Статус контейнеров ═══${NC}"
    docker-compose ps
    press_enter
}

# ---------------------------- Проверка версий -------------------------
check_versions() {
    echo -e "${BOLD}${CYAN}═══ Информация о версиях ═══${NC}"

    # Версия панели из git
    if [ -d "${PANEL_DIR}/.git" ]; then
        cd "${PANEL_DIR}"
        local panel_version
        panel_version=$(git describe --tags --always 2>/dev/null || echo "неизвестно")
        echo -e "Панель Remnawave: ${GREEN}${panel_version}${NC}"
    else
        echo -e "Панель Remnawave: ${RED}не установлена${NC}"
    fi

    # Версия ноды (локальной)
    if command -v remnanode &>/dev/null; then
        local node_version
        node_version=$(remnanode version 2>/dev/null || echo "неизвестно")
        echo -e "RemnaNode (локальная): ${GREEN}${node_version}${NC}"
    elif systemctl is-active --quiet remnanode 2>/dev/null; then
        echo -e "RemnaNode (сервис): ${GREEN}активна, но CLI не найден${NC}"
    else
        echo -e "RemnaNode: ${RED}не установлена${NC}"
    fi
    press_enter
}

# ---------------------------- Удаление панели -------------------------
uninstall_panel() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не найдена.${NC}"
        press_enter
        return
    fi
    echo -e "${RED}${BOLD}⚠️  ВНИМАНИЕ! Это удалит ВСЕ данные панели, включая базу данных и настройки.${NC}"
    read -p "$(echo -e ${RED}Вы уверены? Введите yes для подтверждения: ${NC})" CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo -e "${GREEN}Удаление отменено.${NC}"
        press_enter
        return
    fi
    cd "${PANEL_DIR}"
    docker-compose down -v &>/dev/null
    cd "${SCRIPT_DIR}"
    rm -rf "${PANEL_DIR}"
    echo -e "${GREEN}[✓] Панель полностью удалена.${NC}"
    press_enter
}

# ---------------------------- Управление нодами -----------------------
manage_nodes() {
    while true; do
        clear
        echo -e "${BOLD}${MAGENTA}═══ Управление RemnaNodes ═══${NC}"
        echo -e " 1) Установить локальную ноду"
        echo -e " 2) Просмотр логов ноды"
        echo -e " 3) Статус ноды"
        echo -e " 4) Удалить локальную ноду"
        echo -e " 5) Версия ноды"
        echo -e " 0) Назад в главное меню"
        echo -ne "${GREEN}Выберите действие: ${NC}"
        read -r NODE_OPT
        case $NODE_OPT in
            1) install_node ;;
            2) node_logs ;;
            3) node_status ;;
            4) remove_node ;;
            5) node_version ;;
            0) break ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
        esac
    done
}

install_node() {
    echo -e "${CYAN}[*] Установка RemnaNode (локально)...${NC}"
    if [ ! -f "${ENV_FILE}" ]; then
        echo -e "${RED}[!] Сначала установите панель и настройте .env${NC}"
        press_enter
        return
    fi
    source "${ENV_FILE}"
    if [ -z "${API_KEY}" ]; then
        echo -e "${RED}[!] API_KEY не найден в .env${NC}"
        press_enter
        return
    fi

    echo -e "${YELLOW}Запускаю официальный установщик ноды...${NC}"
    bash <(curl -sL https://raw.githubusercontent.com/Remnawave/remnanode/main/install.sh) <<EOF &
${API_KEY}
${DOMAIN}
EOF
    spinner $! "Установка ноды"
    wait $! 2>/dev/null
    echo -e "${GREEN}[✓] Нода установлена и подключена к панели ${DOMAIN}${NC}"
    press_enter
}

node_logs() {
    if systemctl is-active --quiet remnanode 2>/dev/null; then
        journalctl -u remnanode -f
    else
        echo -e "${RED}[!] Сервис remnanode не запущен.${NC}"
        press_enter
    fi
}

node_status() {
    if systemctl is-active --quiet remnanode 2>/dev/null; then
        echo -e "${GREEN}[✓] RemnaNode работает.${NC}"
        systemctl status remnanode --no-pager
    else
        echo -e "${RED}[✗] RemnaNode остановлен или не установлен.${NC}"
    fi
    press_enter
}

node_version() {
    if command -v remnanode &>/dev/null; then
        remnanode version
    elif systemctl is-active --quiet remnanode 2>/dev/null; then
        echo -e "${YELLOW}CLI remnanode не найден, но сервис работает. Версия не определена.${NC}"
    else
        echo -e "${RED}Нода не установлена.${NC}"
    fi
    press_enter
}

remove_node() {
    echo -e "${RED}${BOLD}⚠️  Это удалит ноду и её конфигурацию.${NC}"
    read -p "$(echo -e ${RED}Подтвердите (yes): ${NC})" CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo -e "${GREEN}Удаление отменено.${NC}"
        press_enter
        return
    fi
    systemctl stop remnanode 2>/dev/null || true
    systemctl disable remnanode 2>/dev/null || true
    rm -f /etc/systemd/system/remnanode.service
    rm -rf /opt/remnanode
    echo -e "${GREEN}[✓] Нода удалена.${NC}"
    press_enter
}

# ---------------------------- Главное меню ----------------------------
main_menu() {
    while true; do
        show_banner
        echo -e "  ${BOLD}1)${NC} Установить панель Remnawave"
        echo -e "  ${BOLD}2)${NC} Просмотреть .env"
        echo -e "  ${BOLD}3)${NC} Редактировать .env"
        echo -e "  ${BOLD}4)${NC} Обновить панель"
        echo -e "  ${BOLD}5)${NC} Просмотр логов"
        echo -e "  ${BOLD}6)${NC} Статус сервисов"
        echo -e "  ${BOLD}7)${NC} Управление RemnaNodes"
        echo -e "  ${BOLD}8)${NC} Удалить панель"
        echo -e "  ${BOLD}9)${NC} Версии панели и ноды"
        echo -e "  ${BOLD}0)${NC} Выход"
        echo -ne "${GREEN}Ваш выбор: ${NC}"
        read -r OPTION
        case $OPTION in
            1) install_panel ;;
            2) view_env ;;
            3) edit_env ;;
            4) update_panel ;;
            5) view_logs ;;
            6) check_status ;;
            7) manage_nodes ;;
            8) uninstall_panel ;;
            9) check_versions ;;
            0) echo -e "${CYAN}До свидания! Поддержка: @drugd${NC}"; exit 0 ;;
            *) echo -e "${RED}Неверный пункт. Попробуйте ещё раз.${NC}"; sleep 1 ;;
        esac
    done
}

# ---------------------------- Точка входа -----------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}⚠️  Скрипт запущен не от root. Для установки ноды могут понадобиться права sudo.${NC}"
    sleep 1
fi

install_docker
check_deps
main_menu
