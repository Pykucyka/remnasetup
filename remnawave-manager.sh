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

# Линейный прогресс-бар
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

# Анимированный спиннер
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

# Установка Docker, если отсутствует
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
        echo -e "  ${YELLOW}Репозиторий уже существует. Пропускаю клонирование.${NC}"
    fi
    cd "${PANEL_DIR}"

    progress_bar 2 4 "Настройка .env"
    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || true
    fi

    echo -e "${YELLOW}${BOLD}Ответьте на вопросы:${NC}"
    read -p "$(echo -e ${GREEN}Введите домен (например panel.example.com): ${NC})" DOMAIN
    read -p "$(echo -e ${GREEN}Придумайте пароль администратора: ${NC})" ADMIN_PASSWORD
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
    echo

    # Генерация секретов
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
        echo -e "\n${BOLD}${CYAN}═══ Содержимое .env ═══${NC}"
        cat "${ENV_FILE}"
    else
        echo -e "\n${RED}[!] Файл .env не найден.${NC}"
    fi
    press_enter
}

edit_env() {
    if [ -f "${ENV_FILE}" ]; then
        echo -e "${YELLOW}Открываю редактор nano. Сохраните изменения и перезапустите панель (пункт 4).${NC}"
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

# ======================== БЭКАП И ВОССТАНОВЛЕНИЕ ====================
backup_panel() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не установлена.${NC}"
        press_enter
        return
    fi
    cd "${PANEL_DIR}"

    if [ ! -f ".env" ]; then
        echo -e "${RED}[!] Не найден .env файл.${NC}"
        press_enter
        return
    fi
    source .env

    local db_service=$(docker-compose config --services 2>/dev/null | grep -i 'db\|postgres' | head -1)
    if [ -z "$db_service" ]; then
        echo -e "${RED}[!] Не удалось определить сервис базы данных.${NC}"
        press_enter
        return
    fi
    echo -e "${YELLOW}Сервис БД: ${db_service}${NC}"

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="${BACKUP_DIR}/${timestamp}"
    mkdir -p "$backup_path"

    echo -e "\n${BOLD}${GREEN}=== Создание резервной копии панели ===${NC}"

    progress_bar 1 3 "Копирование конфигов"
    cp .env docker-compose.yml "$backup_path/" 2>/dev/null || true
    echo -e "  ${GREEN}[✓] .env и docker-compose.yml сохранены.${NC}"

    progress_bar 2 3 "Дамп базы данных"
    echo -e "  ${YELLOW}Выполняю pg_dump...${NC}"
    if docker-compose exec -T "$db_service" pg_dump -U postgres remnawave > "$backup_path/remnawave_db.sql" 2>/dev/null; then
        echo -e "  ${GREEN}[✓] Дамп базы данных создан.${NC}"
    else
        echo -e "  ${RED}[✗] Ошибка дампа. Убедитесь, что контейнер запущен.${NC}"
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
    echo -e "${GREEN}[✓] Резервная копия сохранена: ${BACKUP_DIR}/${archive_name}${NC}"
    press_enter
}

restore_panel() {
    if [ ! -d "${PANEL_DIR}" ]; then
        echo -e "${RED}[!] Панель не установлена. Сначала установите панель хотя бы с пустой конфигурацией.${NC}"
        press_enter
        return
    fi

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
        echo -e "${RED}[!] Нет доступных резервных копий в ${BACKUP_DIR}${NC}"
        press_enter
        return
    fi

    echo -e "\n${BOLD}${GREEN}=== Восстановление панели из резервной копии ===${NC}"
    echo -e "${YELLOW}Доступные бэкапы:${NC}"
    ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true
    echo -ne "${GREEN}Введите имя файла архива (или '0' для выхода): ${NC}"
    read -r archive_name
    if [ "$archive_name" == "0" ]; then
        return
    fi

    local archive_path="${BACKUP_DIR}/${archive_name}"
    if [ ! -f "$archive_path" ]; then
        echo -e "${RED}[!] Файл не найден: $archive_path${NC}"
        press_enter
        return
    fi

    echo -e "${RED}${BOLD}⚠️  Восстановление перезапишет текущие .env и базу данных!${NC}"
    read -p "$(echo -e ${RED}Вы уверены? Введите yes для продолжения: ${NC})" CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo -e "${GREEN}Восстановление отменено.${NC}"
        press_enter
        return
    fi

    local tmp_restore_dir="${SCRIPT_DIR}/restore_tmp"
    rm -rf "$tmp_restore_dir"
    mkdir -p "$tmp_restore_dir"

    echo -e "${CYAN}[1/4] Распаковка архива...${NC}"
    tar xzf "$archive_path" -C "$tmp_restore_dir" &
    spinner $! "Распаковка"

    cd "${PANEL_DIR}"
    echo -e "${CYAN}[2/4] Остановка панели...${NC}"
    docker-compose down &>/dev/null
    echo -e "  ${GREEN}[✓] Контейнеры остановлены.${NC}"

    echo -e "${CYAN}[3/4] Замена .env и docker-compose.yml...${NC}"
    local backup_content_dir=$(find "$tmp_restore_dir" -maxdepth 2 -name ".env" -print -quit | xargs dirname)
    if [ -z "$backup_content_dir" ]; then
        echo -e "${RED}[!] В архиве не найден .env.${NC}"
        rm -rf "$tmp_restore_dir"
        press_enter
        return
    fi
    cp "$backup_content_dir/.env" "$backup_content_dir/docker-compose.yml" "${PANEL_DIR}/" 2>/dev/null || true
    echo -e "  ${GREEN}[✓] Конфиги обновлены.${NC}"

    echo -e "${CYAN}[4/4] Запуск панели и восстановление БД...${NC}"
    docker-compose up -d &>/dev/null &
    spinner $! "Запуск контейнеров"
    sleep 10

    source "${PANEL_DIR}/.env"
    local db_service=$(docker-compose config --services 2>/dev/null | grep -i 'db\|postgres' | head -1)
    if [ -n "$db_service" ]; then
        echo -e "  ${YELLOW}Импорт дампа базы данных...${NC}"
        if docker-compose exec -T "$db_service" psql -U postgres remnawave < "$backup_content_dir/remnawave_db.sql" 2>/dev/null; then
            echo -e "  ${GREEN}[✓] База данных восстановлена.${NC}"
        else
            echo -e "  ${RED}[✗] Ошибка импорта. Попробуйте вручную:${NC}"
            echo -e "  ${YELLOW}docker-compose exec -T $db_service psql -U postgres remnawave < $backup_content_dir/remnawave_db.sql${NC}"
        fi
    else
        echo -e "${RED}[!] Сервис БД не найден, пропускаю импорт дампа.${NC}"
    fi

    rm -rf "$tmp_restore_dir"
    echo -e "\n${GREEN}✅ Восстановление завершено. Панель работает с новыми данными.${NC}"
    press_enter
}

# ======================== ПОДПИСКА ==================================
install_subscription_page() {
    echo -e "\n${BOLD}${GREEN}=== Установка страницы подписок Remnawave ===${NC}"
    mkdir -p "${SUBSCRIPTION_DIR}"
    cd "${SCRIPT_DIR}"

    progress_bar 1 4 "Клонирование"
    if [ ! -d "${SUBSCRIPTION_DIR}/.git" ]; then
        git clone "${REPO_SUB_URL}" "${SUBSCRIPTION_DIR}" &>/dev/null &
        spinner $! "Клонирование репозитория"
    else
        echo -e "  ${YELLOW}Репозиторий уже существует. Пропускаю.${NC}"
    fi
    cd "${SUBSCRIPTION_DIR}"

    progress_bar 2 4 "Настройка .env"
    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || true
    fi

    local panel_api_url="https://CHANGE_ME"
    if [ -f "${ENV_FILE}" ]; then
        source "${ENV_FILE}"
        panel_api_url="https://${DOMAIN}/api"
    fi

    echo -e "${YELLOW}${BOLD}Настройка страницы подписок:${NC}"
    read -p "$(echo -e ${GREEN}Введите домен страницы подписок (например sub.example.com): ${NC})" SUB_DOMAIN
    read -p "$(echo -e ${GREEN}Введите API URL панели [${panel_api_url}]: ${NC})" input_api_url
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
    echo -e "\n${BOLD}${GREEN}✅ Установка завершена!${NC}"
    echo -e "Страница доступна по адресу: ${CYAN}https://${SUB_DOMAIN}${NC}"
    press_enter
}

update_subscription_page() {
    if [ ! -d "${SUBSCRIPTION_DIR}" ]; then
        echo -e "${RED}[!] Страница подписок не установлена.${NC}"
        press_enter
        return
    fi
    cd "${SUBSCRIPTION_DIR}"
    echo -e "\n${CYAN}[*] Обновление страницы подписок...${NC}"
    progress_bar 1 2 "Git pull"
    git pull &>/dev/null &
    spinner $! "Git pull"
    progress_bar 2 2 "Пересборка"
    docker-compose down &>/dev/null
    docker-compose up -d --build &>/dev/null &
    spinner $! "Docker compose up --build"
    echo -e "${GREEN}[✓] Страница подписок обновлена.${NC}"
    press_enter
}

subscription_logs() {
    if [ ! -d "${SUBSCRIPTION_DIR}" ]; then
        echo -e "${RED}[!] Страница подписок не установлена.${NC}"
        press_enter
        return
    fi
    cd "${SUBSCRIPTION_DIR}"
    echo -e "${CYAN}[*] Логи страницы подписок (Ctrl+C для выхода)...${NC}"
    sleep 1
    docker-compose logs -f --tail=100
    press_enter
}

subscription_status() {
    if [ ! -d "${SUBSCRIPTION_DIR}" ]; then
        echo -e "${RED}[!] Страница подписок не установлена.${NC}"
        press_enter
        return
    fi
    cd "${SUBSCRIPTION_DIR}"
    echo -e "\n${BOLD}${CYAN}═══ Статус контейнеров ═══${NC}"
    docker-compose ps
    press_enter
}

remove_subscription_page() {
    if [ ! -d "${SUBSCRIPTION_DIR}" ]; then
        echo -e "${RED}[!] Страница подписок не найдена.${NC}"
        press_enter
        return
    fi
    echo -e "${RED}${BOLD}⚠️  Это удалит страницу подписок и все её данные.${NC}"
    read -p "$(echo -e ${RED}Вы уверены? Введите yes для подтверждения: ${NC})" CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo -e "${GREEN}Удаление отменено.${NC}"
        press_enter
        return
    fi
    cd "${SUBSCRIPTION_DIR}"
    docker-compose down -v &>/dev/null
    cd "${SCRIPT_DIR}"
    rm -rf "${SUBSCRIPTION_DIR}"
    echo -e "${GREEN}[✓] Страница подписок полностью удалена.${NC}"
    press_enter
}

# ======================== НОДА =====================================
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

# ======================== МЕНЮ =====================================
panel_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}═══ Управление панелью Remnawave ═══${NC}"
        echo -e "  ${GREEN} 1)${NC} Установить / Настроить заново"
        echo -e "  ${GREEN} 2)${NC} Просмотреть .env"
        echo -e "  ${GREEN} 3)${NC} Редактировать .env"
        echo -e "  ${GREEN} 4)${NC} Обновить панель"
        echo -e "  ${GREEN} 5)${NC} Логи сервисов"
        echo -e "  ${GREEN} 6)${NC} Статус контейнеров"
        echo -e "  ${GREEN} 7)${NC} Версия панели"
        echo -e "  ${GREEN} 8)${NC} Удалить панель"
        echo -e "  ${GREEN} 9)${NC} 💾 Создать резервную копию"
        echo -e "  ${GREEN}10)${NC} 📥 Восстановить из резервной копии"
        echo -e "  ${GREEN} 0)${NC} Назад в главное меню"
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
            9) backup_panel ;;
            10) restore_panel ;;
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

subscription_menu() {
    while true; do
        clear
        echo -e "${BOLD}${MAGENTA}═══ Управление страницей подписок ═══${NC}"
        echo -e "  ${GREEN}1)${NC} Установить страницу подписок"
        echo -e "  ${GREEN}2)${NC} Обновить страницу подписок"
        echo -e "  ${GREEN}3)${NC} Логи страницы подписок"
        echo -e "  ${GREEN}4)${NC} Статус контейнеров"
        echo -e "  ${GREEN}5)${NC} Удалить страницу подписок"
        echo -e "  ${GREEN}0)${NC} Назад в главное меню"
        echo -ne "${YELLOW}Выберите действие: ${NC}"
        read -r OPT
        case $OPT in
            1) install_subscription_page ;;
            2) update_subscription_page ;;
            3) subscription_logs ;;
            4) subscription_status ;;
            5) remove_subscription_page ;;
            0) break ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
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
        echo -e "${BOLD}${WHITE}            Remnawave Panel & Node Manager v2.2${NC}"
        echo -e "${BOLD}${MAGENTA}       При поддержке ${WHITE}Y-VPN${MAGENTA} | Создатель: ${WHITE}@drugd${MAGENTA} | Канал: ${WHITE}@yurichvpn${NC}"
        echo -e "${DIM}═══════════════════════════════════════════════════════════${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} 🖥️  Панель Remnawave"
        echo -e "  ${GREEN}2)${NC} 📡 RemnaNode"
        echo -e "  ${GREEN}3)${NC} 📄 Страница подписок"
        echo -e "  ${GREEN}0)${NC} 🚪 Выход"
        echo -ne "${YELLOW}Ваш выбор: ${NC}"
        read -r MAIN_OPT
        case $MAIN_OPT in
            1) panel_menu ;;
            2) node_menu ;;
            3) subscription_menu ;;
            0) echo -e "${CYAN}До свидания! Поддержка: @drugd / @yurichvpn${NC}"; exit 0 ;;
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
