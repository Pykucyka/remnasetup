#!/bin/bash
# ======================================================================
#  Remnawave Panel & Node Manager v3.3 (Stable)
#  При поддержке Y-VPN • @drugd • Канал @yurichvpn
#  Репозиторий: https://github.com/Pykucyka/remnasetup
# ======================================================================

set -o pipefail

# ---------------------------- Цвета -----------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'
BOLD='\033[1m'; NC='\033[0m'; DIM='\033[2m'

# ---------------------------- Пути ------------------------------------
SCRIPT_DIR="$(pwd)"
PANEL_DIR="${SCRIPT_DIR}/remnawave-panel"
ENV_FILE="${PANEL_DIR}/.env"
REPO_URL="https://github.com/Remnawave/remnawave.git"
SUBSCRIPTION_DIR="${SCRIPT_DIR}/remnawave-subscription"
REPO_SUB_URL="https://github.com/Remnawave/subscription-page.git"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# ---------------------------- Утилиты ---------------------------------
msg_info()    { echo -e "${CYAN}[*]${NC} $1"; }
msg_success() { echo -e "${GREEN}[+]${NC} $1"; }
msg_error()   { echo -e "${RED}[!]${NC} $1"; }
msg_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }

press_enter() { 
    echo -e "\n${DIM}Нажмите Enter для возврата в меню...${NC}"
    read -r 
}

get_env_val() {
    local file="$1" key="$2"
    if [ -f "$file" ]; then
        grep -E "^${key}=" "$file" | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | tr -d '\n\r'
    fi
}

dc() {
    if docker compose version &>/dev/null; then
        docker compose "$@"
    elif command -v docker-compose &>/dev/null; then
        docker-compose "$@"
    else
        msg_error "Docker Compose не найден!"
        return 1
    fi
}

install_packages() {
    local pkgs=("$@")
    if command -v apt-get &>/dev/null; then
        apt-get update -qq &>/dev/null
        apt-get install -y -qq "${pkgs[@]}" &>/dev/null
    elif command -v dnf &>/dev/null; then
        dnf install -y -q "${pkgs[@]}" &>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y -q "${pkgs[@]}" &>/dev/null
    elif command -v apk &>/dev/null; then
        apk update &>/dev/null
        apk add "${pkgs[@]}" &>/dev/null
    else
        msg_warn "Неизвестный пакетный менеджер. Установите ${pkgs[*]} вручную."
    fi
}

check_deps() {
    local deps=(curl git openssl tar nano)
    local missing=()
    for cmd in "${deps[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        msg_info "Установка недостающих зависимостей: ${missing[*]}"
        install_packages "${missing[@]}"
    fi
}

install_docker() {
    if command -v docker &>/dev/null; then
        msg_success "Docker уже установлен."
        return 0
    fi

    msg_info "Установка Docker (это может занять несколько минут)..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    if sh /tmp/get-docker.sh > /tmp/docker_install.log 2>&1; then
        msg_success "Docker успешно установлен."
    else
        msg_error "Ошибка установки Docker. Последние строки лога:"
        tail -n 20 /tmp/docker_install.log
        exit 1
    fi
    rm -f /tmp/get-docker.sh
    
    systemctl enable --now docker &>/dev/null
    msg_success "Docker готов к работе."
}

safe_clone() {
    local repo_url="$1" target_dir="$2"
    if [ -d "$target_dir/.git" ]; then
        msg_warn "Репозиторий уже существует в $target_dir."
        return 0
    fi
    mkdir -p "$target_dir"
    local i=1
    while [ $i -le 3 ]; do
        if git clone "$repo_url" "$target_dir" &>/dev/null; then
            return 0
        fi
        msg_warn "Попытка клонирования $i/3 не удалась. Повтор через 2 сек..."
        sleep 2
        i=$(( i + 1 ))
    done
    msg_error "Не удалось клонировать $repo_url"
    return 1
}

# ======================== ПАНЕЛЬ =====================================
install_panel() {
    echo -e "\n${BOLD}${GREEN}=== Установка панели Remnawave ===${NC}"
    mkdir -p "${PANEL_DIR}"
    cd "${SCRIPT_DIR}" || exit 1

    safe_clone "${REPO_URL}" "${PANEL_DIR}" || { press_enter; return; }
    cd "${PANEL_DIR}" || exit 1

    [ ! -f ".env" ] && cp .env.example .env 2>/dev/null || true

    echo -e "${YELLOW}${BOLD}Ответьте на вопросы (или нажмите Enter для значений по умолчанию):${NC}"
    
    echo -ne "${GREEN}Домен панели [panel.example.com]: ${NC}"
    read -r DOMAIN
    DOMAIN=${DOMAIN:-panel.example.com}
    
    echo -ne "${GREEN}Пароль администратора [admin]: ${NC}"
    read -r ADMIN_PASSWORD
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
    echo

    cat > .env <<EOF
DOMAIN=${DOMAIN}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
JWT_SECRET=$(openssl rand -hex 32)
API_KEY=$(openssl rand -hex 16)
DB_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
POSTGRES_USER=postgres
POSTGRES_DB=remnawave
EOF

    msg_success ".env успешно сгенерирован."
    
    msg_info "Запуск контейнеров (сборка и старт)..."
    if dc up -d --build > /tmp/dc_panel.log 2>&1; then
        msg_success "Все сервисы запущены."
        echo -e "\n${BOLD}${GREEN}✅ Панель: https://${DOMAIN}${NC}"
        echo -e "Логин: ${BOLD}admin${NC}  Пароль: ${BOLD}${ADMIN_PASSWORD}${NC}"
    else
        msg_error "Ошибка запуска контейнеров. Лог:"
        tail -n 30 /tmp/dc_panel.log
    fi
    press_enter
}

view_env() {
    [ -f "${ENV_FILE}" ] && cat "${ENV_FILE}" || msg_error ".env не найден."
    press_enter
}

edit_env() {
    if [ -f "${ENV_FILE}" ]; then
        nano "${ENV_FILE}"
        msg_success "Редактирование завершено."
    else
        msg_error ".env не найден."
    fi
    press_enter
}

update_panel() {
    [ ! -d "${PANEL_DIR}" ] && { msg_error "Панель не установлена."; press_enter; return; }
    cd "${PANEL_DIR}" || return
    msg_info "Обновление панели..."
    if git pull > /tmp/git_pull.log 2>&1; then
        msg_success "Код обновлен."
    else
        msg_error "Ошибка git pull."
        cat /tmp/git_pull.log
    fi
    dc down &>/dev/null
    msg_info "Пересборка..."
    if dc up -d --build > /tmp/dc_up.log 2>&1; then
        msg_success "Панель обновлена и запущена."
    else
        msg_error "Ошибка пересборки. Лог:"
        tail -n 30 /tmp/dc_up.log
    fi
    press_enter
}

view_logs() {
    [ ! -d "${PANEL_DIR}" ] && { msg_error "Панель не установлена."; press_enter; return; }
    cd "${PANEL_DIR}" || return
    msg_info "Последние 100 строк логов:"
    dc logs --tail=100
    press_enter
}

check_status() {
    [ ! -d "${PANEL_DIR}" ] && { msg_error "Панель не установлена."; press_enter; return; }
    cd "${PANEL_DIR}" || return
    dc ps
    press_enter
}

panel_version() {
    if [ -d "${PANEL_DIR}/.git" ]; then
        cd "${PANEL_DIR}" || return
        echo -e "Версия панели: ${GREEN}$(git describe --tags --always 2>/dev/null || echo 'неизвестно')${NC}"
    else
        msg_error "Не установлена"
    fi
    press_enter
}

uninstall_panel() {
    [ ! -d "${PANEL_DIR}" ] && { msg_error "Панель не найдена."; press_enter; return; }
    echo -ne "${RED}Удалить всё? (yes/no): ${NC}"
    read -r c
    [ "$c" != "yes" ] && return
    cd "${PANEL_DIR}" || return
    dc down -v &>/dev/null
    cd "${SCRIPT_DIR}" || return
    rm -rf "${PANEL_DIR}"
    msg_success "Панель удалена."
    press_enter
}

# ======================== БЭКАП ======================================
backup_panel() {
    [ ! -d "${PANEL_DIR}" ] && { msg_error "Панель не установлена."; press_enter; return; }
    cd "${PANEL_DIR}" || return
    
    local db_container=$(docker ps --format '{{.Names}}' | grep -iE 'postgres|db' | head -n 1)
    if [ -z "$db_container" ]; then
        msg_error "Контейнер базы данных не запущен или не найден."
        press_enter; return
    fi

    local ts=$(date +%Y%m%d_%H%M%S)
    local bp="${BACKUP_DIR}/${ts}"
    mkdir -p "$bp"
    
    cp .env docker-compose.yml "$bp/" 2>/dev/null
    
    local db_user=$(get_env_val .env POSTGRES_USER)
    local db_name=$(get_env_val .env POSTGRES_DB)
    db_user=${db_user:-postgres}
    db_name=${db_name:-remnawave}

    msg_info "Создание дампа базы данных..."
    if docker exec -t "$db_container" pg_dump -U "$db_user" -d "$db_name" > "$bp/remnawave_db.sql" 2>/dev/null; then
        cd "$BACKUP_DIR" || return
        tar czf "remnawave_backup_${ts}.tar.gz" "$ts" &>/dev/null
        rm -rf "$ts"
        msg_success "Бэкап сохранен: ${BACKUP_DIR}/remnawave_backup_${ts}.tar.gz"
    else
        msg_error "Ошибка при создании дампа БД."
        rm -rf "$bp"
    fi
    press_enter
}

restore_panel() {
    [ ! -d "${PANEL_DIR}" ] && { msg_error "Сначала установите панель."; press_enter; return; }
    
    local backups=()
    while IFS= read -r -d '' file; do
        backups+=("$file")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -print0 2>/dev/null)

    if [ ${#backups[@]} -eq 0 ]; then
        msg_error "Нет доступных бэкапов."
        press_enter; return
    fi

    echo -e "${BOLD}Доступные бэкапы:${NC}"
    local i=1
    for b in "${backups[@]}"; do
        echo "  $i) $(basename "$b")"
        i=$((i+1))
    done
    echo "  0) Отмена"
    
    echo -ne "Выберите номер бэкапа: "
    read -r choice
    
    if [ "$choice" -eq 0 ] 2>/dev/null || [ -z "$choice" ]; then return; fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -gt "${#backups[@]}" ]; then
        msg_error "Неверный выбор."
        press_enter; return
    fi

    local archive_path="${backups[$((choice-1))]}"
    echo -ne "${RED}Восстановление перезапишет текущие данные. Продолжить? (yes/no): ${NC}"
    read -r c
    [ "$c" != "yes" ] && return

    local tmp="${SCRIPT_DIR}/restore_tmp"
    rm -rf "$tmp"; mkdir -p "$tmp"
    
    msg_info "Распаковка архива..."
    tar xzf "$archive_path" -C "$tmp" &>/dev/null

    cd "${PANEL_DIR}" || return
    dc down &>/dev/null

    local src=$(find "$tmp" -maxdepth 2 -name .env -print -quit | xargs dirname)
    if [ -z "$src" ]; then
        msg_error "В архиве не найден файл .env."
        rm -rf "$tmp"; press_enter; return
    fi

    cp "$src/.env" "$src/docker-compose.yml" "${PANEL_DIR}/" 2>/dev/null
    
    msg_info "Запуск контейнеров..."
    dc up -d &>/dev/null
    sleep 5 

    local db_container=$(docker ps --format '{{.Names}}' | grep -iE 'postgres|db' | head -n 1)
    if [ -n "$db_container" ] && [ -f "$src/remnawave_db.sql" ]; then
        local db_user=$(get_env_val .env POSTGRES_USER)
        local db_name=$(get_env_val .env POSTGRES_DB)
        db_user=${db_user:-postgres}
        db_name=${db_name:-remnawave}
        
        msg_info "Импорт базы данных..."
        if docker exec -i "$db_container" psql -U "$db_user" -d "$db_name" < "$src/remnawave_db.sql" &>/dev/null; then
            msg_success "База данных успешно восстановлена."
        else
            msg_error "Возникли ошибки при импорте БД."
        fi
    fi
    
    rm -rf "$tmp"
    press_enter
}

# ======================== ПОДПИСКА ==================================
install_subscription_page() {
    echo -e "\n${BOLD}${GREEN}=== Установка страницы подписок ===${NC}"
    mkdir -p "${SUBSCRIPTION_DIR}"
    cd "${SCRIPT_DIR}" || exit 1
    
    safe_clone "${REPO_SUB_URL}" "${SUBSCRIPTION_DIR}" || { press_enter; return; }
    cd "${SUBSCRIPTION_DIR}" || exit 1

    [ ! -f ".env" ] && cp .env.example .env 2>/dev/null || true

    local api_url="https://CHANGE_ME"
    if [ -f "${ENV_FILE}" ]; then
        local panel_domain=$(get_env_val "${ENV_FILE}" "DOMAIN")
        [ -n "$panel_domain" ] && api_url="https://${panel_domain}/api"
    fi

    echo -ne "${GREEN}Домен подписки [sub.example.com]: ${NC}"
    read -r SUB_DOMAIN
    SUB_DOMAIN=${SUB_DOMAIN:-sub.example.com}
    
    echo -ne "${GREEN}API URL панели [${api_url}]: ${NC}"
    read -r input_api
    api_url=${input_api:-$api_url}

    cat > .env <<EOF
SUBSCRIPTION_DOMAIN=${SUB_DOMAIN}
REMNAWAVE_API_URL=${api_url}
SUB_SECRET=$(openssl rand -hex 16)
EOF

    msg_info "Запуск контейнеров подписки..."
    if dc up -d --build > /tmp/dc_sub.log 2>&1; then
        msg_success "Страница подписок развернута: https://${SUB_DOMAIN}"
    else
        msg_error "Ошибка запуска. Лог:"
        tail -n 20 /tmp/dc_sub.log
    fi
    press_enter
}

update_subscription_page() {
    [ ! -d "${SUBSCRIPTION_DIR}" ] && { msg_error "Не установлена."; press_enter; return; }
    cd "${SUBSCRIPTION_DIR}" || return
    git pull &>/dev/null
    dc up -d --build &>/dev/null
    msg_success "Обновлено."
    press_enter
}

subscription_logs() { 
    [ -d "${SUBSCRIPTION_DIR}" ] && cd "${SUBSCRIPTION_DIR}" && dc logs --tail=100 || msg_error "Не установлена."
    press_enter
}

subscription_status() { 
    [ -d "${SUBSCRIPTION_DIR}" ] && cd "${SUBSCRIPTION_DIR}" && dc ps || msg_error "Не установлена."
    press_enter
}

remove_subscription_page() {
    [ ! -d "${SUBSCRIPTION_DIR}" ] && { msg_error "Не найдена."; press_enter; return; }
    echo -ne "Удалить? (yes/no): "
    read -r c
    [ "$c" != "yes" ] && return
    cd "${SUBSCRIPTION_DIR}" || return
    dc down -v &>/dev/null
    cd "${SCRIPT_DIR}" || return
    rm -rf "${SUBSCRIPTION_DIR}"
    msg_success "Удалена."
    press_enter
}

# ======================== НОДА =====================================
install_node() {
    echo -e "\n${BOLD}${GREEN}=== Установка RemnaNode ===${NC}"
    if [ ! -f "${ENV_FILE}" ]; then
        msg_error "Сначала установите панель, чтобы получить API_KEY."
        press_enter; return
    fi
    
    local api_key=$(get_env_val "${ENV_FILE}" "API_KEY")
    local domain=$(get_env_val "${ENV_FILE}" "DOMAIN")
    
    if [ -z "$api_key" ] || [ -z "$domain" ]; then
        msg_error "Не удалось получить API_KEY или DOMAIN из .env панели."
        press_enter; return
    fi

    msg_warn "Запускаю официальный установщик RemnaNode..."
    msg_warn "Следуйте инструкциям в терминале. Если установщик запросит данные, введите их."
    sleep 2
    
    # Запускаем синхронно, без фона, чтобы установщик мог работать с TTY
    bash <(curl -fsSL https://raw.githubusercontent.com/Remnawave/remnanode/main/install.sh)
    
    msg_success "Работа установщика завершена."
    press_enter
}

node_logs() { 
    systemctl is-active --quiet remnanode && journalctl -u remnanode -n 50 || { msg_error "Сервис не активен."; press_enter; }
}

node_status() { 
    systemctl is-active --quiet remnanode && systemctl status remnanode || { msg_error "Не активна."; press_enter; }
}

node_version() { 
    command -v remnanode &>/dev/null && remnanode version || msg_error "Версия не определена."
    press_enter
}

remove_node() {
    echo -ne "Удалить ноду? (yes/no): "
    read -r c
    [ "$c" != "yes" ] && return
    systemctl stop remnanode 2>/dev/null; systemctl disable remnanode 2>/dev/null
    rm -f /etc/systemd/system/remnanode.service; rm -rf /opt/remnanode
    msg_success "Нода удалена."
    press_enter
}

# ======================== МЕНЮ =====================================
panel_menu() {
    clear
    while true; do
        echo -e "${BOLD}${CYAN}═══ Панель Remnawave ═══${NC}"
        echo -e " 1) Установить   6) Статус"
        echo -e " 2) Показать .env  7) Версия"
        echo -e " 3) Редактировать .env 8) Удалить"
        echo -e " 4) Обновить   9) Бэкап"
        echo -e " 5) Логи (последние 100) 10) Восстановить"
        echo -e " 0) Назад"
        echo -ne "> "
        read -r o
        case $o in
            1) install_panel; clear ;; 
            2) view_env; clear ;;
            3) edit_env; clear ;;
            4) update_panel; clear ;;
            5) view_logs; clear ;;
            6) check_status; clear ;;
            7) panel_version; clear ;;
            8) uninstall_panel; clear ;;
            9) backup_panel; clear ;;
            10) restore_panel; clear ;;
            0) return ;;
            *) echo -e "\n${YELLOW}Неверный выбор. Повторите.${NC}" ;;
        esac
    done
}

node_menu() {
    clear
    while true; do
        echo -e "${BOLD}${MAGENTA}═══ Нода ═══${NC}"
        echo -e "1) Установить  2) Логи  3) Статус  4) Версия  5) Удалить  0) Назад"
        echo -ne "> "
        read -r o
        case $o in
            1) install_node; clear ;; 
            2) node_logs; clear ;; 
            3) node_status; clear ;; 
            4) node_version; clear ;; 
            5) remove_node; clear ;; 
            0) return ;;
            *) echo -e "\n${YELLOW}Неверный выбор. Повторите.${NC}" ;;
        esac
    done
}

subscription_menu() {
    clear
    while true; do
        echo -e "${BOLD}${MAGENTA}═══ Подписка ═══${NC}"
        echo -e "1) Установить  2) Обновить  3) Логи  4) Статус  5) Удалить  0) Назад"
        echo -ne "> "
        read -r o
        case $o in
            1) install_subscription_page; clear ;; 
            2) update_subscription_page; clear ;; 
            3) subscription_logs; clear ;;
            4) subscription_status; clear ;; 
            5) remove_subscription_page; clear ;; 
            0) return ;;
            *) echo -e "\n${YELLOW}Неверный выбор. Повторите.${NC}" ;;
        esac
    done
}

main_menu() {
    clear
    while true; do
        echo -e "${CYAN}${BOLD}"
        echo "██████╗ ███████╗███╗   ███╗███╗   ██╗ █████╗ ██╗    ██╗ █████╗ ██╗   ██╗███████╗"
        echo "██╔══██╗██╔════╝████╗ ████║████╗  ██║██╔══██╗██║    ██║██╔══██╗██║   ██║██╔════╝"
        echo "██████╔╝█████╗  ██╔████╔██║██╔██╗ ██║███████║██║ █╗ ██║███████║██║   ██║█████╗  "
        echo "██╔══██╗██╔══╝  ██║╚██╔╝██║██║╚██╗██║██╔══██║██║███╗██║██╔══██║╚██╗ ██╔╝██╔══╝  "
        echo "██║  ██║███████╗██║ ╚═╝ ██║██║ ╚████║██║  ██║╚███╔███╔╝██║  ██║ ╚████╔╝ ███████╗"
        echo "╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚══╝╚═══╝ ╚═╝  ╚═╝  ╚═══╝  ╚══════╝"
        echo -e "${NC}"
        echo -e "${BOLD}${WHITE}            Remnawave Manager v3.3${NC}"
        echo -e "${BOLD}${MAGENTA}        Y-VPN | @drugd | @yurichvpn${NC}"
        echo -e "${DIM}══════════════════════════════════════════${NC}"
        echo -e "  ${GREEN}1)${NC} 🖥️  Панель"
        echo -e "  ${GREEN}2)${NC} 📡 Нода"
        echo -e "  ${GREEN}3)${NC} 📄 Подписка"
        echo -e "  ${GREEN}0)${NC} 🚪 Выход"
        echo -ne "> "
        read -r o
        case $o in
            1) panel_menu ;; 
            2) node_menu ;; 
            3) subscription_menu ;; 
            0) exit 0 ;;
            *) echo -e "\n${YELLOW}Неверный выбор. Повторите.${NC}" ;;
        esac
    done
}

# ---------------------------- Entry point -----------------------------
if [[ $EUID -ne 0 ]]; then
    msg_warn "Скрипт запущен не от имени root."
    msg_warn "Для установки ноды и управления systemd-сервисами root ОБЯЗАТЕЛЕН."
    sleep 2
fi

install_docker
check_deps
main_menu
