Вот стильный `README.md` для вашего репозитория — готов к копипасте, будет отлично смотреться на GitHub:

```markdown
<p align="center">
  <img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&size=30&duration=3000&pause=500&color=00BFFF&center=true&vCenter=true&width=600&lines=Remnawave+Panel+%26+Node+Manager" alt="Typing SVG" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.1-blue?style=for-the-badge" />
  <img src="https://img.shields.io/badge/shell-bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" />
  <img src="https://img.shields.io/badge/docker-ready-2496ED?style=for-the-badge&logo=docker&logoColor=white" />
  <img src="https://img.shields.io/badge/support-Y--VPN-FF5722?style=for-the-badge&logo=telegram&logoColor=white" />
</p>

<h3 align="center">✨ Автоматическая установка, управление и мониторинг Remnawave ✨</h3>

<p align="center">
  <b>При поддержке <a href="https://t.me/yvpn">Y-VPN</a> | Создатель: <a href="https://t.me/drugd">@drugd</a></b>
</p>

---

## 🚀 Возможности

- 🖥 **Полная автоустановка** панели Remnawave и локальной ноды
- 📝 **Удобное управление** переменными окружения `.env` (просмотр, редактирование)
- 🔄 **Обновление** панели до последней версии одной командой
- 📊 **Просмотр логов** и статуса всех контейнеров
- 🧹 **Удаление** панели и ноды с очисткой данных
- 📌 **Проверка версий** установленных компонентов (панель, нода)
- 🎨 **Красивый TUI** с прогресс-барами и цветным интерфейсом
- 🛡 **Улучшенная обработка ошибок** с детальными подсказками
- 🐳 Автоматическая установка Docker и docker-compose при необходимости

## 📦 Быстрый старт

```bash
git clone https://github.com/yourname/remnawave-manager.git
cd remnawave-manager
bash remnawave-manager.sh
```

> [!IMPORTANT]
> Для установки локальной ноды требуются права **root**.  
> Скрипт предупредит, если запущен от обычного пользователя.

## 🧩 Меню скрипта

```
═══ Remnawave Panel & Node Manager v1.1 ═══

 1) Установить панель Remnawave
 2) Просмотреть .env
 3) Редактировать .env
 4) Обновить панель
 5) Просмотр логов
 6) Статус сервисов
 7) Управление RemnaNodes
 8) Удалить панель
 9) Версии панели и ноды
 0) Выход
```

## 📂 Структура репозитория

```
remnawave-manager/
├── remnawave-manager.sh   # основной скрипт-менеджер
└── README.md
```

После установки панели появится директория `remnawave-panel/` со всеми файлами Docker Compose.

## 🔧 Требования

- Ubuntu/Debian (рекомендуется 20.04+)
- Доступ в интернет
- Права root или sudo (для установки ноды)
- (Опционально) установленный Docker — если отсутствует, скрипт установит его автоматически

## ❤️ Поддержка и контакты

Возникли вопросы или предложения? Пишите:

- Telegram канал Y-VPN: [@yvpn](https://t.me/yvpn)
- Создатель скрипта: [@drugd](https://t.me/drugd)

---

<p align="center">
  <sub>© 2026 Y-VPN | Remnawave Manager | Made with ❤️ by @drugd</sub>
</p>
```

