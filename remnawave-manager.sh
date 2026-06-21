#!/bin/bash
# ======================================================================
#  Remnawave Panel & Node Manager v2.2
#  При поддержке Y-VPN • @drugd • Канал @yurichvpn
#  Репозиторий: https://github.com/Pykucyka/remnasetup
# ======================================================================
set -Eeuo pipefail
trap 'echo -e "\n${RED}[!] Прервано пользователем.${NC}"; exit 1' INT
trap 'error_handler $? $LINENO' ERR

# ---------------------------- Цвета -----------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'; DIM='\033[2m'

# ---------------------------- Пути ------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANEL_DIR="${SCRIPT_DIR}/remnawave-panel"
ENV_FILE="${PANEL_DIR}/.env"
REPO_URL="https://github.com/Remnawave/remnawave.git"
SUBSCRIPTION_DIR="${SCRIPT_DIR}/remnawave-subscription"
REPO_SUB_URL="https://github.com/Remnawave/subscription-page.git"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# ---------------------------- Функции ---------------------------------
error_handler() {
    echo -e "\n${RED}${BOLD}[ОШИБКА]${NC} Код: ${RED}$1${NC}, строка: ${RED}$2${NC}"
    echo -e "${YELLOW}Проверьте лог или обратитесь в поддержку @drugd${NC}"
    exit $1
}

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
    [ $step -eq $total ] && echo
}

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

press_enter() {
    echo -e "\n${DIM}Нажмите Enter для продолжения...${NC}"
    read -r
}

check_deps() {
    for cmd in curl git docker docker-compose; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}[!] $cmd не найден. Установите его и повторите запуск.${NC}"
            exit 1
        fi
    done
}

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
        if apt update -qq && apt install -y docker-compose &>/dev/null; then
            echo -e "${GREEN}[+] docker-compose установлен через apt.${NC}"
        else
            echo -e "${YELLOW}[*] Скачиваю docker-compose вручную...${NC}"
            local url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
            curl -L "$url" -o /usr/local/bin/docker-compose &>/dev/null &
            spinner $! "Загрузка docker-compose"
            chmod +x /usr/local/bin/docker-compose
            echo -e "${GREEN}[+] docker-compose установлен вручную.${NC}"
        fi
    fi
}

# ======================== ПАНЕЛЬ =====================================
install_panel() {
    echo -e "\n${BOLD}${GREEN}=== Установка панели Remnawave ===${NC}"
    mkdir -p "${PANEL_DIR}"
    cd "${SCRIPT_DIR}"

    progress_bar 1 4 "Клонирование"
    if [ ! -d "${PANEL_DIR}/.git" ]; then
        git clone "${REPO_URL}" "${PANEL_DIR}" &>/dev/null &
        spinner $! "Клонирование репозитория"
    else
        echo -e "  ${YELLOW}Репозиторий уже существует. Пропускаю.${NC}"
    fi
    cd "${PANEL_DIR}"

    progress_bar 2 4 "Настройка .env"
    [ ! -f ".env" ] && cp .env.example .env 2>/dev/null || true

    echo -e "${YELLOW}${BOLD}Ответьте на вопросы:${NC}"
    read -p "$(echo -e ${GREEN}Введите домен (например panel.example.com): ${NC})" DOMAIN
    read -p "$(echo -e ${GREEN}Придумайте пароль администратора: ${NC})" ADMIN_PASSWORD
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
    echo

    JWT_SECRET=$(openssl rand -hex 32)
    API_KEY=$(openssl rand -hex 16)
    DB_PASSWORD=$(openssl rand -hex 16)
    REDIS_PASSWORD=$(openssl rand -hex 16)

    cat > .env <<EOF
DOMAIN=${DOMAIN}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
JWT_SECRET=${JWT_SECRET}
API_KEY=${API_KEY}
DB_PASSWORD=${DB_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
EOF

    echo -e "  ${GREEN}[✓] .env записан.${NC}"

    progress_bar 3 4 "Запуск контейнеров"
    docker-compose up -d &>/dev/null &
    spinner $! "Docker Compose up"

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
        cat "${ENV_FILE}"
    else
        echo -e "\n${RED}[!] Файл .env не найден.${NC}"
    fi
    press_enter
}

edit_env() {
    if [ -f "${ENV_FILE}" ]; then
        nano "${ENV_FILE}"
        echo -e "${GREEN}[✓] Редактирование завершено.${NC}"
    else
        echo -e "${RED}[!] Файл .env не найден.${NC}"
    fi
    press_enter
}

update_panel() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}[!] Панель не установлена.${NC}"; press_enter; return; }
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
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}[!] Панель не установлена.${NC}"; press_enter; return; }
    cd "${PANEL_DIR}"
    echo -e "${CYAN}[*] Логи сервисов (Ctrl+C для выхода)...${NC}"
    sleep 1
    docker-compose logs -f --tail=100
    press_enter
}

check_status() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}[!] Панель не установлена.${NC}"; press_enter; return; }
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
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}[!] Панель не найдена.${NC}"; press_enter; return; }
    echo -e "${RED}${BOLD}⚠️  Это удалит ВСЕ данные панели!${NC}"
    read -p "$(echo -e ${RED}Введите yes для подтверждения: ${NC})" CONFIRM
    [ "$CONFIRM" != "yes" ] && { echo -e "${GREEN}Удаление отменено.${NC}"; press_enter; return; }
    cd "${PANEL_DIR}"
    docker-compose down -v &>/dev/null
    cd "${SCRIPT_DIR}"
    rm -rf "${PANEL_DIR}"
    echo -e "${GREEN}[✓] Панель полностью удалена.${NC}"
    press_enter
}

# ======================== БЭКАП И ВОССТАНОВЛЕНИЕ ====================
backup_panel() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}[!] Панель не установлена.${NC}"; press_enter; return; }
    cd "${PANEL_DIR}"
    [ ! -f ".env" ] && { echo -e "${RED}[!] .env не найден.${NC}"; press_enter; return; }
    source .env

    local db_service=$(docker-compose config --services 2>/dev/null | grep -i 'db\|postgres' | head -1)
    [ -z "$db_service" ] && { echo -e "${RED}[!] Сервис БД не определён.${NC}"; press_enter; return; }
    echo -e "${YELLOW}Сервис БД: ${db_service}${NC}"

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="${BACKUP_DIR}/${timestamp}"
    mkdir -p "$backup_path"

    echo -e "\n${BOLD}${GREEN}=== Создание резервной копии ===${NC}"
    progress_bar 1 3 "Копирование конфигов"
    cp .env docker-compose.yml "$backup_path/"
    echo -e "  ${GREEN}[✓] Конфиги сохранены.${NC}"

    progress_bar 2 3 "Дамп базы данных"
    if docker-compose exec -T "$db_service" pg_dump -U postgres remnawave > "$backup_path/remnawave_db.sql" 2>/dev/null; then
        echo -e "  ${GREEN}[✓] Дамп БД создан.${NC}"
    else
        echo -e "  ${RED}[✗] Ошибка дампа.${NC}"
        rm -rf "$backup_path"
        press_enter
        return
    fi

    progress_bar 3 3 "Архивация"
    local archive_name="remnawave_backup_${timestamp}.tar.gz"
    cd "$BACKUP_DIR"
    tar czf "$archive_name" "$timestamp" &>/dev/null &
    spinner $! "Упаковка в архив"
    rm -rf "$timestamp"
    echo -e "${GREEN}[✓] Бэкап сохранён: ${BACKUP_DIR}/${archive_name}${NC}"
    press_enter
}

restore_panel() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}[!] Панель не установлена.${NC}"; press_enter; return; }
    [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ] && {
        echo -e "${RED}[!] Нет доступных бэкапов.${NC}"; press_enter; return;
    }

    echo -e "\n${BOLD}${GREEN}=== Восстановление из бэкапа ===${NC}"
    echo -e "${YELLOW}Доступные архивы:${NC}"
    ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true
    echo -ne "${GREEN}Введите имя файла (или 0 для выхода): ${NC}"
    read -r archive_name
    [ "$archive_name" = "0" ] && return

    local archive_path="${BACKUP_DIR}/${archive_name}"
    [ ! -f "$archive_path" ] && { echo -e "${RED}[!] Файл не найден.${NC}"; press_enter; return; }

    echo -e "${RED}${BOLD}⚠️  Это перезапишет текущую панель!${NC}"
    read -p "$(echo -e ${RED}Введите yes для продолжения: ${NC})" CONFIRM
    [ "$CONFIRM" != "yes" ] && { echo -e "${GREEN}Отменено.${NC}"; press_enter; return; }

    local tmp_restore_dir="${SCRIPT_DIR}/restore_tmp"
    rm -rf "$tmp_restore_dir"
    mkdir -p "$tmp_restore_dir"

    echo -e "${CYAN}[1/4] Распаковка...${NC}"
    tar xzf "$archive_path" -C "$tmp_restore_dir" &
    spinner $! "Распаковка"

    cd "${PANEL_DIR}"
    echo -e "${CYAN}[2/4] Остановка панели...${NC}"
    docker-compose down &>/dev/null
    echo -e "  ${GREEN}[✓] Контейнеры остановлены.${NC}"

    echo -e "${CYAN}[3/4] Замена конфигов...${NC}"
    local backup_content_dir=$(find "$tmp_restore_dir" -maxdepth 2 -name ".env" -print -quit | xargs dirname)
    [ -z "$backup_content_dir" ] && { echo -e "${RED}[!] В архиве нет .env.${NC}"; rm -rf "$tmp_restore_dir"; press_enter; return; }
    cp "$backup_content_dir/.env" "$backup_content_dir/docker-compose.yml" "${PANEL_DIR}/"
    echo -e "  ${GREEN}[✓] Конфиги обновлены.${NC}"

    echo -e "${CYAN}[4/4] Запуск и восстановление БД...${NC}"
    docker-compose up -d &>/dev/null &
    spinner $! "Запуск контейнеров"
    sleep 10

    source "${PANEL_DIR}/.env"
    local db_service=$(docker-compose config --services 2>/dev/null | grep -i 'db\|postgres' | head -1)
    if [ -n "$db_service" ]; then
        if docker-compose exec -T "$db_service" psql -U postgres remnawave < "$backup_content_dir/remnawave_db.sql" 2>/dev/null; then
            echo -e "  ${GREEN}[✓] База данных восстановлена.${NC}"
        else
            echo -e "  ${RED}[✗] Ошибка импорта БД. Выполните вручную:${NC}"
            echo -e "  ${YELLOW}docker-compose exec -T $db_service psql -U postgres remnawave < $backup_content_dir/remnawave_db.sql${NC}"
        fi
    else
        echo -e "${RED}[!] Сервис БД не найден, пропускаю импорт дампа.${NC}"
    fi

    rm -rf "$tmp_restore_dir"
    echo -e "\n${GREEN}✅ Восстановление завершено.${NC}"
    press_enter
}

# ======================== ПОДПИСКА ==================================
install_subscription_page() {
    echo -e "\n${BOLD}${GREEN}=== Установка страницы подписок ===${NC}"
    mkdir -p "${SUBSCRIPTION_DIR}"
    cd "${SCRIPT_DIR}"

    progress_bar 1 4 "Клонирование"
    if [ ! -d "${SUBSCRIPTION_DIR}/.git" ]; then
        git clone "${REPO_SUB_URL}" "${SUBSCRIPTION_DIR}" &>/dev/null &
        spinner $! "Клонирование репозитория"
    else
        echo -e "  ${YELLOW}Репозиторий уже существует.${NC}"
    fi
    cd "${SUBSCRIPTION_DIR}"

    progress_bar 2 4 "Настройка .env"
    [ ! -f ".env" ] && cp .env.example .env 2>/dev/null || true

    local panel_api_url="https://CHANGE_ME"
    [ -f "${ENV_FILE}" ] && { source "${ENV_FILE}"; panel_api_url="https://${DOMAIN}/api"; }

    echo -e "${YELLOW}${BOLD}Настройка страницы подписок:${NC}"
    read -p "$(echo -e ${GREEN}Домен страницы (например sub.example.com): ${NC})" SUB_DOMAIN
    read -p "$(echo -e ${GREEN}API URL панели [${panel_api_url}]: ${NC})" input_api_url
    local api_url=${input_api_url:-$panel_api_url}
    local SUB_SECRET=$(openssl rand -hex 16)

    cat > .env <<EOF
SUBSCRIPTION_DOMAIN=${SUB_DOMAIN}
REMNAWAVE_API_URL=${api_url}
SUB_SECRET=${SUB_SECRET}
EOF
    echo -e "  ${GREEN}[✓] .env записан.${NC}"

    progress_bar 3 4 "Запуск контейнеров"
    docker-compose up -d &>/dev/null &
    spinner $! "Docker Compose up"

    progress_bar 4 4 "Ожидание готовности"
    sleep 3
    echo -e "${GREEN}[✓] Страница подписок запущена.${NC}"
    echo -e "\n${BOLD}${GREEN}✅ Страница доступна: https://${SUB_DOMAIN}${NC}"
    press_enter
}

update_subscription_page() {
    [ ! -d "${SUBSCRIPTION_DIR}" ] && { echo -e "${RED}[!] Не установлена.${NC}"; press_enter; return; }
    cd "${SUBSCRIPTION_DIR}"
    progress_bar 1 2 "Обновление"
    git pull &>/dev/null &
    spinner $! "Git pull"
    progress_bar 2 2 "Пересборка"
    docker-compose down &>/dev/null
    docker-compose up -d --build &>/dev/null &
    spinner $! "Docker compose up --build"
    echo -e "${GREEN}[✓] Обновлено.${NC}"
    press_enter
}

subscription_logs() {
    [ ! -d "${SUBSCRIPTION_DIR}" ] && { echo -e "${RED}[!] Не установлена.${NC}"; press_enter; return; }
    cd "${SUBSCRIPTION_DIR}"
    docker-compose logs -f --tail=100
    press_enter
}

subscription_status() {
    [ ! -d "${SUBSCRIPTION_DIR}" ] && { echo -e "${RED}[!] Не установлена.${NC}"; press_enter; return; }
    cd "${SUBSCRIPTION_DIR}"
    docker-compose ps
    press_enter
}

remove_subscription_page() {
    [ ! -d "${SUBSCRIPTION_DIR}" ] && { echo -e "${RED}[!] Не найдена.${NC}"; press_enter; return; }
    read -p "$(echo -e ${RED}Удалить? (yes): ${NC})" CONFIRM
    [ "$CONFIRM" != "yes" ] && return
    cd "${SUBSCRIPTION_DIR}"
    docker-compose down -v &>/dev/null
    cd "${SCRIPT_DIR}"
    rm -rf "${SUBSCRIPTION_DIR}"
    echo -e "${GREEN}[✓] Удалена.${NC}"
    press_enter
}

# ======================== НОДА =====================================
install_node() {
    echo -e "\n${BOLD}${GREEN}=== Установка RemnaNode ===${NC}"
    [ ! -f "${ENV_FILE}" ] && { echo -e "${RED}[!] Сначала установите панель.${NC}"; press_enter; return; }
    source "${ENV_FILE}"
    [ -z "${API_KEY}" ] && { echo -e "${RED}[!] API_KEY не найден.${NC}"; press_enter; return; }

    echo -e "${YELLOW}Запускаю официальный установщик ноды...${NC}"
    bash <(curl -sL https://raw.githubusercontent.com/Remnawave/remnanode/main/install.sh) <<EOF &
${API_KEY}
${DOMAIN}
EOF
    spinner $! "Установка ноды"
    echo -e "${GREEN}[✓] Нода подключена к ${DOMAIN}${NC}"
    press_enter
}

node_logs() {
    systemctl is-active --quiet remnanode 2>/dev/null && journalctl -u remnanode -f || {
        echo -e "${RED}[!] Сервис remnanode не запущен.${NC}"; press_enter;
    }
}

node_status() {
    systemctl is-active --quiet remnanode 2>/dev/null && systemctl status remnanode || {
        echo -e "${RED}[✗] RemnaNode остановлена или не установлена.${NC}"; press_enter;
    }
}

node_version() {
    command -v remnanode &>/dev/null && remnanode version || {
        echo -e "${RED}Нода не установлена или версия не определена.${NC}"; press_enter;
    }
}

remove_node() {
    echo -e "${RED}${BOLD}⚠️  Это удалит ноду!${NC}"
    read -p "$(echo -e ${RED}Подтвердите (yes): ${NC})" CONFIRM
    [ "$CONFIRM" != "yes" ] && return
    systemctl stop remnanode 2>/dev/null || true
    systemctl disable remnanode 2>/dev/null || true
    rm -f /etc/systemd/system/remnanode.service
    rm -rf /opt/remnanode
    echo -e "${GREEN}[✓] Нода удалена.${NC}"
    press_enter
}

# ======================== МЕНЮ =====================================
panel_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}═══ Панель Remnawave ═══${NC}"
        echo -e "  ${GREEN} 1)${NC} Установить"
        echo -e "  ${GREEN} 2)${NC} .env"
        echo -e "  ${GREEN} 3)${NC} Редактировать .env"
        echo -e "  ${GREEN} 4)${NC} Обновить"
        echo -e "  ${GREEN} 5)${NC} Логи"
        echo -e "  ${GREEN} 6)${NC} Статус"
        echo -e "  ${GREEN} 7)${NC} Версия"
        echo -e "  ${GREEN} 8)${NC} Удалить"
        echo -e "  ${GREEN} 9)${NC} 💾 Бэкап"
        echo -e "  ${GREEN}10)${NC} 📥 Восстановить"
        echo -e "  ${GREEN} 0)${NC} Назад"
        read -p "> " o
        case $o in
            1) install_panel;; 2) view_env;; 3) edit_env;; 4) update_panel;; 5) view_logs;;
            6) check_status;; 7) panel_version;; 8) uninstall_panel;; 9) backup_panel;;
            10) restore_panel;; 0) break;;
        esac
    done
}

node_menu() {
    while true; do
        clear
        echo -e "${BOLD}${MAGENTA}═══ Нода ═══${NC}"
        echo -e "1) Установить  2) Логи  3) Статус  4) Версия  5) Удалить  0) Назад"
        read -p "> " o
        case $o in
            1) install_node;; 2) node_logs;; 3) node_status;; 4) node_version;; 5) remove_node;; 0) break;;
        esac
    done
}

subscription_menu() {
    while true; do
        clear
        echo -e "${BOLD}${MAGENTA}═══ Подписка ═══${NC}"
        echo -e "1) Установить  2) Обновить  3) Логи  4) Статус  5) Удалить  0) Назад"
        read -p "> " o
        case $o in
            1) install_subscription_page;; 2) update_subscription_page;; 3) subscription_logs;;
            4) subscription_status;; 5) remove_subscription_page;; 0) break;;
        esac
    done
}

main_menu() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        echo "  ██████╗ ███████╗███╗   ███╗███╗   ██╗ █████╗ ██╗    ██╗ █████╗ ██╗   ██╗███████╗"
        echo "  ██╔══██╗██╔════╝████╗ ████║████╗  ██║██╔══██╗██║    ██║██╔══██╗██║   ██║██╔════╝"
        echo "  ██████╔╝█████╗  ██╔████╔██║██╔██╗ ██║███████║██║ █╗ ██║███████║██║   ██║█████╗  "
        echo "  ██╔══██╗██╔══╝  ██║╚██╔╝██║██║╚██╗██║██╔══██║██║███╗██║██╔══██║╚██╗ ██╔╝██╔══╝  "
        echo "  ██║  ██║███████╗██║ ╚═╝ ██║██║ ╚████║██║  ██║╚███╔███╔╝██║  ██║ ╚████╔╝ ███████╗"
        echo "  ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝  ╚═══╝  ╚══════╝"
        echo -e "${NC}"
        echo -e "${BOLD}${WHITE}            Remnawave Manager v2.2${NC}"
        echo -e "${BOLD}${MAGENTA}        Y-VPN | @drugd | @yurichvpn${NC}"
        echo -e "${DIM}══════════════════════════════════════════${NC}"
        echo -e "  ${GREEN}1)${NC} 🖥️  Панель"
        echo -e "  ${GREEN}2)${NC} 📡 Нода"
        echo -e "  ${GREEN}3)${NC} 📄 Подписка"
        echo -e "  ${GREEN}0)${NC} 🚪 Выход"
        read -p "> " o
        case $o in
            1) panel_menu;; 2) node_menu;; 3) subscription_menu;; 0) exit 0;;
        esac
    done
}

# ---------------------------- Entry point -----------------------------
[[ $EUID -ne 0 ]] && echo -e "${YELLOW}⚠️  Рекомендуется root${NC}" && sleep 1
install_docker
check_deps
main_menu
