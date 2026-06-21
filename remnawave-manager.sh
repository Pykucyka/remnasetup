#!/bin/bash
# ======================================================================
#  Remnawave Panel & Node Manager — Ультимативный автоустановщик v2.0
#  При поддержке Y-VPN  •  Создатель: Telegram @drugd  •  Канал @yurichvpn
# ======================================================================
#  Запуск: bash remnawave-manager.sh
#  Репозиторий: https://github.com/Pykucyka/remnasetup
# ======================================================================
set -Eeuo pipefail
trap 'echo -e "\n${RED}[!] Прервано пользователем.${NC}"; exit 1' INT
trap 'error_handler $? $LINENO' ERR

# ---------------------------- Цвета -----------------------------------
RED='\033[0;31m';     GREEN='\033[0;32m';   YELLOW='\033[1;33m'
BLUE='\033[0;34m';    CYAN='\033[0;36m';    MAGENTA='\033[0;35m'
WHITE='\033[1;37m';   BOLD='\033[1m';       NC='\033[0m'
DIM='\033[2m'

# ---------------------------- Пути ------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANEL_DIR="${SCRIPT_DIR}/remnawave-panel"
ENV_FILE="${PANEL_DIR}/.env"
REPO_URL="https://github.com/Remnawave/remnawave.git"

# ---------------------------- Функции ---------------------------------
error_handler() {
    echo -e "\n${RED}${BOLD}[ОШИБКА]${NC} Код: ${RED}$1${NC}, строка: ${RED}$2${NC}"
    echo -e "${YELLOW}Пожалуйста, проверьте лог или обратитесь в поддержку @drugd${NC}"
    exit $1
}

# Прогресс-бар с процентами (линейный, для последовательных шагов)
progress_bar() {
    local step=$1 total=$2 message=$3
    local percent=$(( step * 100 / total ))
    local width=40
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    printf "\r  ${CYAN}%-20s${NC} [${GREEN}" "$message"
    printf "%${filled}s" '' | tr ' ' '█'
    printf "${DIM}"
    printf "%${empty}s" '' | tr ' ' '░'
    printf "${NC}] %3d%%" "$percent"
    if [ $step -eq $total ]; then echo; fi
}

# Спиннер для параллельных операций (используем c fork)
spinner() {
    local pid=$1 message=$2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local delay=0.1
    printf "  ${CYAN}%s...${NC}   " "$message"
    while kill -0 "$pid" 2>/dev/null; do
        for ((i=0; i<${#spinstr}; i++)); do
            printf "\b${spinstr:$i:1}"
            sleep $delay
        done
    done
    wait "$pid" 2>/dev/null
    local exit_code=$?
    printf "\r  ${GREEN}✔ %s${NC}    \n" "$message"
    return $exit_code
}

# Пресс Enter
press_enter() {
    echo -e "\n${DIM}Нажмите Enter для продолжения...${NC}"
    read -r
}

# Проверка зависимостей
check_deps() {
    for cmd in curl git docker docker-compose; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}[!] $cmd не найден. Установите его и повторите запуск.${NC}"
            exit 1
        fi
    done
}

# Автоустановка Docker
install_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${YELLOW}[*] Docker не обнаружен. Устанавливаю...${NC}"
        curl -fsSL https://get.docker.com | bash &>/dev/null &
        spinner $! "Установка Docker"
        systemctl enable --now docker &>/dev/null
        echo -e "${GREEN}[+] Docker готов.${NC}"
    fi
    if ! command -v docker-compose &>/dev/null; then
        echo -e "${YELLOW}[*] Устанавливаю docker-compose...${NC}"
        apt update -qq && apt install -y docker-compose &>/dev/null || {
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose &>/dev/null &
            spinner $! "Загрузка docker-compose"
            chmod +x /usr/local/bin/docker-compose
        }
        echo -e "${GREEN}[+] docker-compose готов.${NC}"
    fi
}

# ---------------------- Работа с панелью ------------------------------
install_panel() {
    echo -e "\n${BOLD}${GREEN}=== Установка панели Remnawave ===${NC}"
    mkdir -p "${PANEL_DIR}"
    cd "${SCRIPT_DIR}"

    # Шаг 1: Клонирование
    progress_bar 1 4 "Клонирование репозитория"
    if [ ! -d "${PANEL_DIR}/.git" ]; then
        git clone "${REPO_URL}" "${PANEL_DIR}" &>/dev/null &
        spinner $! "Клонирование"
    else
        echo -e "  ${YELLOW}Репозиторий уже существует. Пропускаю.${NC}"
    fi
    cd "${PANEL_DIR}"

    # Шаг 2: Настройка .env
    progress_bar 2 4 "Настройка окружения"
    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || true
    fi

    echo -e "${YELLOW}${BOLD}Ответьте на несколько вопросов:${NC}"
    read -p "$(echo -e ${GREEN}Введите ваш домен (например, panel.example.com): ${NC})" DOMAIN
    read -p "$(echo -e ${GREEN}Придумайте пароль администратора: ${NC})" ADMIN_PASSWORD
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
    echo

    JWT_SECRET=$(openssl rand -hex 32)
    API_KEY=$(openssl rand -hex 16)
    cat > .env <<EOF
# Remnawave .env — сгенерировано автоматически
DOMAIN=${DOMAIN}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
JWT_SECRET=${JWT_SECRET}
API_KEY=${API_KEY}
DB_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
EOF
    echo -e "  ${GREEN}[✓] .env записан.${NC}"

    # Шаг 3: Запуск
    progress_bar 3 4 "Запуск контейнеров"
    docker-compose up -d &>/dev/null &
    spinner $! "Docker Compose up"

    # Шаг 4: Ожидание
    progress_bar 4 4 "Ожидание готовности"
    sleep 5
    echo -e "${GREEN}[✓] Все сервисы запущены.${NC}"
    echo -e "\n${BOLD}${GREEN}✅ Установка завершена!${NC}"
    echo -e "Панель доступна по адресу: ${CYAN}https://${DOMAIN}${NC}"
    echo -e "Логин: ${BOLD}admin${NC}  Пароль: ${BOLD}${ADMIN_PASSWORD}${NC}"
    press_enter
}

view_env() {
    if [ -f "${ENV_FILE}" ]; then
        echo -e "\n${BOLD}${CYAN}═══ Содержимое .env ═══${NC}"
        cat "${ENV_FILE}"
    else
        echo -e "\n${RED}[!] Файл .env не найден.${NC}"
    fi
    press_enter
}

edit_env() {
    if [ -f "${ENV_FILE}" ]; then
        echo -e "${YELLOW}Открываю редактор (nano). Сохраните изменения и перезапустите панель.${NC}"
        nano "${ENV_FILE}"
        echo -e "${GREEN}[✓] Редактирование завершено.${NC}"
    else
        echo -e "${RED}[!] Файл .env не найден.${NC}"
    fi
    press_enter
}

update_panel() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не установлена.${NC}"
        press_enter
        return
    fi
    cd "${PANEL_DIR}"
    echo -e "\n${CYAN}[*] Обновление панели...${NC}"
    progress_bar 1 2 "Получение обновлений"
    git pull &>/dev/null &
    spinner $! "Git pull"

    progress_bar 2 2 "Пересборка контейнеров"
    docker-compose down &>/dev/null
    docker-compose up -d --build &>/dev/null &
    spinner $! "Docker compose up --build"
    echo -e "${GREEN}[✓] Панель обновлена.${NC}"
    press_enter
}

view_logs() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не установлена.${NC}"
        press_enter
        return
    fi
    cd "${PANEL_DIR}"
    echo -e "${CYAN}[*] Логи сервисов (Ctrl+C для выхода)...${NC}"
    sleep 1
    docker-compose logs -f --tail=100
    press_enter
}

check_status() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не установлена.${NC}"
        press_enter
        return
    fi
    cd "${PANEL_DIR}"
    echo -e "\n${BOLD}${CYAN}═══ Статус контейнеров ═══${NC}"
    docker-compose ps
    press_enter
}

panel_version() {
    if [ -d "${PANEL_DIR}/.git" ]; then
        cd "${PANEL_DIR}"
        echo -e "Версия панели: ${GREEN}$(git describe --tags --always 2>/dev/null || echo 'неизвестно')${NC}"
    else
        echo -e "Панель: ${RED}не установлена${NC}"
    fi
    press_enter
}

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

# ---------------------- Работа с нодой --------------------------------
install_node() {
    echo -e "\n${BOLD}${GREEN}=== Установка RemnaNode ===${NC}"
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
    echo -e "${GREEN}[✓] Нода подключена к панели ${DOMAIN}${NC}"
    press_enter
}

node_logs() {
    if systemctl is-active --quiet remnanode 2>/dev/null; then
        echo -e "${CYAN}[*] Логи ноды (Ctrl+C для выхода)...${NC}"
        journalctl -u remnanode -f
    else
        echo -e "${RED}[!] Сервис remnanode не запущен.${NC}"
        press_enter
    fi
}

node_status() {
    if systemctl is-active --quiet remnanode 2>/dev/null; then
        echo -e "\n${GREEN}[✓] RemnaNode работает.${NC}"
        systemctl status remnanode --no-pager
    else
        echo -e "${RED}[✗] RemnaNode остановлен или не установлен.${NC}"
    fi
    press_enter
}

node_version() {
    if command -v remnanode &>/dev/null; then
        echo -e "Версия ноды: ${GREEN}$(remnanode version 2>/dev/null || echo 'неизвестно')${NC}"
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

# ---------------------- Главное меню ----------------------------------
main_menu() {
    while true; do
        clear
        # Баннер
        echo -e "${CYAN}${BOLD}"
        echo "  ██████╗ ███████╗███╗   ███╗███╗   ██╗ █████╗ ██╗    ██╗ █████╗ ██╗   ██╗███████╗"
        echo "  ██╔══██╗██╔════╝████╗ ████║████╗  ██║██╔══██╗██║    ██║██╔══██╗██║   ██║██╔════╝"
        echo "  ██████╔╝█████╗  ██╔████╔██║██╔██╗ ██║███████║██║ █╗ ██║███████║██║   ██║█████╗  "
        echo "  ██╔══██╗██╔══╝  ██║╚██╔╝██║██║╚██╗██║██╔══██║██║███╗██║██╔══██║╚██╗ ██╔╝██╔══╝  "
        echo "  ██║  ██║███████╗██║ ╚═╝ ██║██║ ╚████║██║  ██║╚███╔███╔╝██║  ██║ ╚████╔╝ ███████╗"
        echo "  ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝  ╚═══╝  ╚══════╝"
        echo -e "${NC}"
        echo -e "${BOLD}${WHITE}            Remnawave Panel & Node Manager v2.0${NC}"
        echo -e "${BOLD}${MAGENTA}       При поддержке ${WHITE}Y-VPN${MAGENTA} | Создатель: ${WHITE}@drugd${MAGENTA} | Канал: ${WHITE}@yurichvpn${NC}"
        echo -e "${DIM}═══════════════════════════════════════════════════════════${NC}"
        echo
        echo -e "${BOLD}${CYAN}Выберите раздел:${NC}"
        echo -e "  ${GREEN}1)${NC} 🖥️  ${BOLD}Панель Remnawave${NC} (установка, обновление, управление)"
        echo -e "  ${GREEN}2)${NC} 📡 ${BOLD}RemnaNode${NC} (установка, логи, удаление)"
        echo -e "  ${GREEN}0)${NC} 🚪 Выход"
        echo -ne "${YELLOW}Ваш выбор: ${NC}"
        read -r MAIN_OPT
        case $MAIN_OPT in
            1) panel_menu ;;
            2) node_menu ;;
            0) echo -e "${CYAN}До свидания! Поддержка: @drugd / @yurichvpn${NC}"; exit 0 ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
        esac
    done
}

panel_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}═══ Управление панелью Remnawave ═══${NC}"
        echo -e "  ${GREEN}1)${NC} Установить / Настроить заново"
        echo -e "  ${GREEN}2)${NC} Просмотреть .env"
        echo -e "  ${GREEN}3)${NC} Редактировать .env"
        echo -e "  ${GREEN}4)${NC} Обновить панель"
        echo -e "  ${GREEN}5)${NC} Логи сервисов"
        echo -e "  ${GREEN}6)${NC} Статус контейнеров"
        echo -e "  ${GREEN}7)${NC} Версия панели"
        echo -e "  ${GREEN}8)${NC} Удалить панель"
        echo -e "  ${GREEN}0)${NC} Назад в главное меню"
        echo -ne "${YELLOW}Выберите действие: ${NC}"
        read -r OPT
        case $OPT in
            1) install_panel ;;
            2) view_env ;;
            3) edit_env ;;
            4) update_panel ;;
            5) view_logs ;;
            6) check_status ;;
            7) panel_version ;;
            8) uninstall_panel ;;
            0) break ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
        esac
    done
}

node_menu() {
    while true; do
        clear
        echo -e "${BOLD}${MAGENTA}═══ Управление RemnaNode ═══${NC}"
        echo -e "  ${GREEN}1)${NC} Установить ноду"
        echo -e "  ${GREEN}2)${NC} Логи ноды"
        echo -e "  ${GREEN}3)${NC} Статус ноды"
        echo -e "  ${GREEN}4)${NC} Версия ноды"
        echo -e "  ${GREEN}5)${NC} Удалить ноду"
        echo -e "  ${GREEN}0)${NC} Назад в главное меню"
        echo -ne "${YELLOW}Выберите действие: ${NC}"
        read -r OPT
        case $OPT in
            1) install_node ;;
            2) node_logs ;;
            3) node_status ;;
            4) node_version ;;
            5) remove_node ;;
            0) break ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
        esac
    done
}

# ---------------------------- Точка входа -----------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}⚠️  Рекомендуется запуск от root (особенно для установки ноды).${NC}"
    sleep 1
fi

install_docker
check_deps
main_menu
