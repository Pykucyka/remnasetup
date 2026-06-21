#!/bin/bash
# ======================================================================
#  Remnawave Panel & Node Manager v2.5
#  При поддержке Y-VPN • @drugd • Канал @yurichvpn
#  Репозиторий: https://github.com/Pykucyka/remnasetup
# ======================================================================
set -Eeuo pipefail
trap 'echo -e "\n${RED}[!] Прервано.${NC}"; exit 1' INT
trap 'error_handler $? $LINENO' ERR

# ---------------------------- Цвета -----------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'
BOLD='\033[1m'; NC='\033[0m'; DIM='\033[2m'

# ---------------------------- Пути ------------------------------------
SCRIPT_DIR="$(pwd)"                                  # работаем в текущей папке
PANEL_DIR="${SCRIPT_DIR}/remnawave-panel"
ENV_FILE="${PANEL_DIR}/.env"
REPO_URL="https://github.com/Remnawave/remnawave.git"
SUBSCRIPTION_DIR="${SCRIPT_DIR}/remnawave-subscription"
REPO_SUB_URL="https://github.com/Remnawave/subscription-page.git"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# ---------------------------- Функции ---------------------------------
error_handler() {
    echo -e "\n${RED}${BOLD}[ОШИБКА]${NC} Код: ${RED}$1${NC} строка: ${RED}$2${NC}"
    echo -e "${YELLOW}Проверьте лог или напишите @drugd${NC}"
    exit $1
}

press_enter() { echo -e "\n${DIM}Нажмите Enter...${NC}"; read -r; }

# Прогресс-бар (простейший и надёжный)
progress_bar() {
    local step=$1 total=$2 msg=$3
    local pct=$(( step * 100 / total ))
    local w=30
    local f=$(( pct * w / 100 ))
    local e=$(( w - f ))
    local filled=$(printf "%${f}s" '' | tr ' ' '█')
    local empty=$(printf "%${e}s" '' | tr ' ' '░')
    printf "\r  ${CYAN}%-20s${NC} [${GREEN}%s${DIM}%s${NC}] %3d%%" "$msg" "$filled" "$empty" "$pct"
    [ "$step" -eq "$total" ] && echo
}

# Спиннер (работает без C‑style for)
spinner() {
    local pid=$1 msg=$2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local delay=0.1
    printf "  ${CYAN}%s...${NC}   " "$msg"
    while kill -0 "$pid" 2>/dev/null; do
        local i=0
        while [ $i -lt ${#spinstr} ]; do
            printf "\b%s" "${spinstr:$i:1}"
            sleep $delay
            i=$(( i + 1 ))
        done
    done
    wait "$pid" 2>/dev/null
    local ec=$?
    printf "\r  ${GREEN}✔ %s${NC}    \n" "$msg"
    return $ec
}

# Скачивание файла (curl или wget)
download_file() {
    local url="$1" output="$2"
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$output" || return 1
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$output" || return 1
    else
        echo -e "${RED}Нет ни curl, ни wget.${NC}"
        return 1
    fi
}

# Установка Docker
install_docker() {
    if command -v docker &>/dev/null && command -v docker-compose &>/dev/null; then
        return
    fi

    echo -e "${YELLOW}[*] Установка Docker...${NC}"
    download_file "https://get.docker.com" "/tmp/get-docker.sh" || {
        echo -e "${RED}Не удалось загрузить установщик Docker.${NC}"
        exit 1
    }
    bash /tmp/get-docker.sh &>/dev/null &
    spinner $! "Установка Docker"
    rm -f /tmp/get-docker.sh
    systemctl enable --now docker &>/dev/null
    echo -e "${GREEN}[+] Docker готов.${NC}"

    if ! command -v docker-compose &>/dev/null; then
        echo -e "${YELLOW}[*] Установка docker-compose...${NC}"
        if apt update -qq && apt install -y docker-compose &>/dev/null; then
            echo -e "${GREEN}[+] docker-compose установлен через apt.${NC}"
        else
            local arch=$(uname -m) os=$(uname -s)
            local url="https://github.com/docker/compose/releases/latest/download/docker-compose-${os}-${arch}"
            download_file "$url" "/usr/local/bin/docker-compose" || {
                echo -e "${RED}Не удалось загрузить docker-compose.${NC}"
                exit 1
            }
            chmod +x /usr/local/bin/docker-compose
            echo -e "${GREEN}[+] docker-compose установлен вручную.${NC}"
        fi
    fi
}

# Проверка зависимостей
check_deps() {
    for cmd in curl wget git; do
        command -v $cmd &>/dev/null || {
            echo -e "${YELLOW}Устанавливаю $cmd...${NC}"
            apt update -qq && apt install -y $cmd 2>/dev/null || true
        }
    done
}

# Безопасное клонирование (3 попытки)
safe_clone() {
    local repo_url="$1" target_dir="$2"
    mkdir -p "$target_dir"
    if [ -d "$target_dir/.git" ]; then
        echo -e "  ${YELLOW}Репозиторий уже существует.${NC}"
        return 0
    fi
    local i=1
    while [ $i -le 3 ]; do
        if git clone "$repo_url" "$target_dir" &>/dev/null; then
            return 0
        fi
        echo -e "  ${YELLOW}Повторная попытка ($i/3)...${NC}"
        sleep 2
        i=$(( i + 1 ))
    done
    echo -e "${RED}[!] Не удалось клонировать $repo_url${NC}"
    return 1
}

# ======================== ПАНЕЛЬ =====================================
install_panel() {
    echo -e "\n${BOLD}${GREEN}=== Установка панели Remnawave ===${NC}"
    mkdir -p "${PANEL_DIR}"
    cd "${SCRIPT_DIR}"

    progress_bar 1 4 "Клонирование"
    safe_clone "${REPO_URL}" "${PANEL_DIR}" || { press_enter; return; }
    cd "${PANEL_DIR}"

    progress_bar 2 4 "Настройка .env"
    [ ! -f ".env" ] && cp .env.example .env 2>/dev/null || true

    echo -e "${YELLOW}${BOLD}Ответьте на вопросы:${NC}"
    read -p "$(echo -e ${GREEN}Домен панели (например panel.example.com): ${NC})" DOMAIN
    read -p "$(echo -e ${GREEN}Пароль администратора: ${NC})" ADMIN_PASSWORD
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
    echo

    cat > .env <<EOF
DOMAIN=${DOMAIN}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
JWT_SECRET=$(openssl rand -hex 32)
API_KEY=$(openssl rand -hex 16)
DB_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
EOF

    echo -e "  ${GREEN}[✓] .env записан.${NC}"

    progress_bar 3 4 "Запуск контейнеров"
    docker-compose up -d &>/dev/null &
    spinner $! "Docker Compose up"

    progress_bar 4 4 "Ожидание готовности"
    sleep 5
    echo -e "${GREEN}[✓] Все сервисы запущены.${NC}"
    echo -e "\n${BOLD}${GREEN}✅ Панель: https://${DOMAIN}${NC}"
    echo -e "Логин: ${BOLD}admin${NC}  Пароль: ${BOLD}${ADMIN_PASSWORD}${NC}"
    press_enter
}

view_env() {
    [ -f "${ENV_FILE}" ] && cat "${ENV_FILE}" || echo -e "\n${RED}.env не найден.${NC}"
    press_enter
}

edit_env() {
    [ -f "${ENV_FILE}" ] && nano "${ENV_FILE}" && echo -e "${GREEN}[✓] Редактирование завершено.${NC}" || echo -e "${RED}.env не найден.${NC}"
    press_enter
}

update_panel() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}Панель не установлена.${NC}"; press_enter; return; }
    cd "${PANEL_DIR}"
    echo -e "\n${CYAN}[*] Обновление панели...${NC}"
    git pull &>/dev/null &
    spinner $! "Git pull"
    docker-compose down &>/dev/null
    docker-compose up -d --build &>/dev/null &
    spinner $! "Пересборка"
    echo -e "${GREEN}[✓] Панель обновлена.${NC}"
    press_enter
}

view_logs() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}Панель не установлена.${NC}"; press_enter; return; }
    cd "${PANEL_DIR}"
    docker-compose logs -f --tail=100
    press_enter
}

check_status() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}Панель не установлена.${NC}"; press_enter; return; }
    cd "${PANEL_DIR}"
    docker-compose ps
    press_enter
}

panel_version() {
    [ -d "${PANEL_DIR}/.git" ] && cd "${PANEL_DIR}" && echo -e "Версия панели: ${GREEN}$(git describe --tags --always 2>/dev/null || echo 'неизвестно')${NC}" || echo -e "${RED}Не установлена${NC}"
    press_enter
}

uninstall_panel() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}Панель не найдена.${NC}"; press_enter; return; }
    read -p "$(echo -e ${RED}Удалить всё? (yes): ${NC})" c
    [ "$c" != "yes" ] && return
    cd "${PANEL_DIR}"
    docker-compose down -v &>/dev/null
    cd "${SCRIPT_DIR}"
    rm -rf "${PANEL_DIR}"
    echo -e "${GREEN}[✓] Панель удалена.${NC}"
    press_enter
}

# ======================== БЭКАП ======================================
backup_panel() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}Панель не установлена.${NC}"; press_enter; return; }
    cd "${PANEL_DIR}"
    source .env
    local db=$(docker-compose config --services 2>/dev/null | grep -i 'db\|postgres' | head -1)
    [ -z "$db" ] && { echo -e "${RED}Сервис БД не найден.${NC}"; press_enter; return; }
    local ts=$(date +%Y%m%d_%H%M%S) bp="${BACKUP_DIR}/${ts}"
    mkdir -p "$bp"
    cp .env docker-compose.yml "$bp/"
    docker-compose exec -T "$db" pg_dump -U postgres remnawave > "$bp/remnawave_db.sql" 2>/dev/null || {
        echo -e "${RED}Ошибка дампа БД.${NC}"; rm -rf "$bp"; press_enter; return;
    }
    cd "$BACKUP_DIR"
    tar czf "remnawave_backup_${ts}.tar.gz" "$ts" &>/dev/null &
    spinner $! "Архивация"
    rm -rf "$ts"
    echo -e "${GREEN}[✓] Бэкап: ${BACKUP_DIR}/remnawave_backup_${ts}.tar.gz${NC}"
    press_enter
}

restore_panel() {
    [ ! -d "${PANEL_DIR}" ] && { echo -e "${RED}Сначала установите панель.${NC}"; press_enter; return; }
    [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ] && { echo -e "${RED}Нет бэкапов.${NC}"; press_enter; return; }
    echo -e "Доступные бэкапы:"
    ls -1 "$BACKUP_DIR"/*.tar.gz
    read -p "Имя архива: " archive; [ "$archive" = "0" ] && return
    local archive_path="${BACKUP_DIR}/${archive}"
    [ ! -f "$archive_path" ] && { echo -e "${RED}Не найден.${NC}"; press_enter; return; }
    read -p "Перезаписать всё? (yes): " c; [ "$c" != "yes" ] && return
    local tmp="${SCRIPT_DIR}/restore_tmp"; rm -rf "$tmp"; mkdir -p "$tmp"
    tar xzf "$archive_path" -C "$tmp" &>/dev/null &
    spinner $! "Распаковка"
    cd "${PANEL_DIR}"; docker-compose down &>/dev/null
    local src=$(find "$tmp" -maxdepth 2 -name .env -print -quit | xargs dirname)
    [ -z "$src" ] && { echo -e "${RED}Нет .env в архиве.${NC}"; rm -rf "$tmp"; press_enter; return; }
    cp "$src/.env" "$src/docker-compose.yml" "${PANEL_DIR}/"
    docker-compose up -d &>/dev/null &
    spinner $! "Запуск"; sleep 10
    source .env
    local db=$(docker-compose config --services 2>/dev/null | grep -i 'db\|postgres' | head -1)
    if [ -n "$db" ]; then
        docker-compose exec -T "$db" psql -U postgres remnawave < "$src/remnawave_db.sql" 2>/dev/null && echo -e "${GREEN}БД восстановлена${NC}" || echo -e "${RED}Ошибка импорта БД${NC}"
    fi
    rm -rf "$tmp"
    press_enter
}

# ======================== ПОДПИСКА ==================================
install_subscription_page() {
    echo -e "\n${BOLD}${GREEN}=== Установка страницы подписок ===${NC}"
    mkdir -p "${SUBSCRIPTION_DIR}"
    cd "${SCRIPT_DIR}"
    progress_bar 1 4 "Клонирование"
    safe_clone "${REPO_SUB_URL}" "${SUBSCRIPTION_DIR}" || { press_enter; return; }
    cd "${SUBSCRIPTION_DIR}"
    progress_bar 2 4 "Настройка .env"
    [ ! -f ".env" ] && cp .env.example .env 2>/dev/null || true
    local api="https://CHANGE_ME"
    [ -f "${ENV_FILE}" ] && { source "${ENV_FILE}"; api="https://${DOMAIN}/api"; }
    read -p "$(echo -e ${GREEN}Домен подписки (sub.example.com): ${NC})" SUB_DOMAIN
    read -p "$(echo -e ${GREEN}API URL панели [${api}]: ${NC})" input_api
    api=${input_api:-$api}
    cat > .env <<EOF
SUBSCRIPTION_DOMAIN=${SUB_DOMAIN}
REMNAWAVE_API_URL=${api}
SUB_SECRET=$(openssl rand -hex 16)
EOF
    progress_bar 3 4 "Запуск контейнеров"
    docker-compose up -d &>/dev/null &
    spinner $! "Docker Compose up"
    progress_bar 4 4 "Готовность"
    sleep 3
    echo -e "\n${GREEN}✅ Страница: https://${SUB_DOMAIN}${NC}"
    press_enter
}

update_subscription_page() {
    [ ! -d "${SUBSCRIPTION_DIR}" ] && { echo -e "${RED}Не установлена.${NC}"; press_enter; return; }
    cd "${SUBSCRIPTION_DIR}"
    git pull &>/dev/null &
    spinner $! "Обновление"
    docker-compose up -d --build &>/dev/null &
    spinner $! "Пересборка"
    echo -e "${GREEN}[✓] Обновлено.${NC}"
    press_enter
}

subscription_logs() { [ -d "${SUBSCRIPTION_DIR}" ] && cd "${SUBSCRIPTION_DIR}" && docker-compose logs -f --tail=100 || echo -e "${RED}Не установлена.${NC}"; press_enter; }
subscription_status() { [ -d "${SUBSCRIPTION_DIR}" ] && cd "${SUBSCRIPTION_DIR}" && docker-compose ps || echo -e "${RED}Не установлена.${NC}"; press_enter; }

remove_subscription_page() {
    [ ! -d "${SUBSCRIPTION_DIR}" ] && { echo -e "${RED}Не найдена.${NC}"; press_enter; return; }
    read -p "Удалить? (yes): " c; [ "$c" != "yes" ] && return
    cd "${SUBSCRIPTION_DIR}"; docker-compose down -v &>/dev/null
    cd "${SCRIPT_DIR}"; rm -rf "${SUBSCRIPTION_DIR}"
    echo -e "${GREEN}[✓] Удалена.${NC}"
    press_enter
}

# ======================== НОДА =====================================
install_node() {
    echo -e "\n${BOLD}${GREEN}=== Установка RemnaNode ===${NC}"
    [ ! -f "${ENV_FILE}" ] && { echo -e "${RED}Сначала установите панель.${NC}"; press_enter; return; }
    source "${ENV_FILE}"
    [ -z "${API_KEY}" ] && { echo -e "${RED}API_KEY не найден в .env.${NC}"; press_enter; return; }
    echo -e "${YELLOW}Запускаю официальный установщик...${NC}"
    bash <(curl -fsSL https://raw.githubusercontent.com/Remnawave/remnanode/main/install.sh) <<EOF &
${API_KEY}
${DOMAIN}
EOF
    spinner $! "Установка ноды"
    echo -e "${GREEN}[✓] Нода подключена к ${DOMAIN}${NC}"
    press_enter
}

node_logs() { systemctl is-active --quiet remnanode && journalctl -u remnanode -f || { echo -e "${RED}Сервис не активен.${NC}"; press_enter; }; }
node_status() { systemctl is-active --quiet remnanode && systemctl status remnanode || echo -e "${RED}Не активна.${NC}"; press_enter; }
node_version() { command -v remnanode &>/dev/null && remnanode version || echo -e "${RED}Версия не определена.${NC}"; press_enter; }

remove_node() {
    read -p "Удалить ноду? (yes): " c; [ "$c" != "yes" ] && return
    systemctl stop remnanode 2>/dev/null; systemctl disable remnanode 2>/dev/null
    rm -f /etc/systemd/system/remnanode.service; rm -rf /opt/remnanode
    echo -e "${GREEN}[✓] Нода удалена.${NC}"
    press_enter
}

# ======================== МЕНЮ =====================================
panel_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}═══ Панель Remnawave ═══${NC}"
        echo -e " 1) Установить  2) .env  3) Редактировать .env  4) Обновить"
        echo -e " 5) Логи  6) Статус  7) Версия  8) Удалить  9) Бэкап  10) Восстановить  0) Назад"
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
        echo -e "${BOLD}${WHITE}            Remnawave Manager v2.5${NC}"
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
[[ $EUID -ne 0 ]] && echo -e "${YELLOW}⚠️  Рекомендуется root (для ноды обязателен).${NC}" && sleep 1
install_docker
check_deps
main_menu
