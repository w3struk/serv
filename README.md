# 3x-ui + Caddy + VLESS + XHTTP — схема проксирования (XHTTP-only)

## Настройка сервера

### Подготовка

- Зарегистрирован и делегирован домен (например, `mydomain.com`), указывающий на ваш VPS

<details>
<summary>Настройка SSH</summary>

### Генерация ключа

```bash
ssh-keygen -t ed25519
```

При выполнении вам предложат изменить место хранения ключа и добавить пароль. Менять локацию не надо, пароль добавьте для безопасности.

### Копирование публичного ключа на VPS

**Linux:**
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub ваш_пользователь@ваша_vps
```

**Windows (PowerShell):**
```powershell
ssh-copy-id -i $env:USERPROFILE\.ssh\id_ed25519.pub ваш_пользователь@ваша_vps
```

Если `ssh-copy-id` не работает на Windows:
```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ваш_пользователь@ваша_vps "cat >> .ssh/authorized_keys"
```

### Отключение входа по паролю

Создайте файл конфигурации:
```bash
sudo nano /etc/ssh/sshd_config.d/00-disable-password.conf
```

Добавьте:
```
Port 22
PasswordAuthentication no
```

Перезапустите SSH:
```bash
sudo systemctl restart ssh
```
</details>

<details>
<summary>Установка Docker</summary>

Инструкции: https://docs.docker.com/engine/install/

**Быстрая установка:**
```bash
bash <(wget -qO- https://get.docker.com)
```

### Запуск Docker без root

```bash
sudo usermod -aG docker $USER
newgrp docker
```
</details>

## Развёртывание

Скрипт полностью интерактивный. При запуске он запросит домен и предпочтительные логин/пароль для панели. Подписка XHTTP создаётся автоматически.

```bash
bash <(curl -sL https://raw.githubusercontent.com/w3struk/serv/main/setup.sh)
```

Или через wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/w3struk/serv/main/setup.sh)
```

Скрипт сам склонирует репозиторий в `/opt/serv` и запустит установку.

> [!NOTE]
> Скрипт нужно запускать от root, так как настраивает BBR и firewall.

### Возможности 

- **Единый Inbound:** Создаётся только VLESS-XHTTP-Backend (UDS, h2c). Публичный TLS завершает Caddy.
- **Безопасность панели:** Настраивает Basic Auth для панели через Caddy, скрывая ее за случайным путем.
- **Управление подписками:** Подписка XHTTP с одним UUID для всех клиентов.

### Требования к Xray-клиенту

Расширенная XHTTP-обфускация рассчитана на **Xray-core v26.6.1**. Для распространения конфигурации используется обычная VLESS-подписка 3x-ui

В VLESS URI параметры `path`, `host` и `mode` передаются отдельно, `xPaddingBytes` дополнительно доступен как `x_padding_bytes`, а полный набор клиентских XHTTP-полей находится в URL-кодированном JSON-параметре `extra`.

## Архитектура проксирования

```
Клиент (VLESS/XHTTP)
       │
       │ TLS :443
       ▼
┌──────────────────────────────────────────────┐
│ Caddy  (public TLS termination)              │
│   /admin-xxxx/* → 3x-ui panel      :2053     │
│   /sub-xxxx/*   → 3x-ui sub service :2096    │
│   /api/vXXX/*   → XHTTP  (h2c+PROXYv2, UDS)  │
└─────────────────────┬────────────────────────┘
                      │ PROXY v2 (real client IP)
                      ▼
┌──────────────────────────────────────────────┐
│ 3x-ui  VLESS-XHTTP-Backend (inbound only)    │
│  streamSettings.sockopt:                     │
│    acceptProxyProtocol: true                  │
│  listen: @uds_xhttp  (Unix Domain Socket)    │
│  network: xhttp, mode: auto                  │
└──────────────────────────────────────────────┘
```

## Управление и Полезные команды

Скрипт `setup.sh` предоставляет несколько встроенных команд:

```bash
./setup.sh                  # Первоначальная установка (интерактивный режим)
./setup.sh add-client       # Добавление нового клиента к существующей установке
./setup.sh status           # Просмотр статуса контейнеров, ссылок, путей и портов
./setup.sh cleanup-vision   # Удаление устаревшего VLESS-TCP-Vision-Frontend
./setup.sh help             # Справка по командами скрипта
```

**Работа с Docker:**
```bash
# Перезапуск всех сервисов и просмотр логов
docker compose down && docker compose up -d && docker compose logs -f

# Обновление 3x-ui до последней версии
docker compose down 3xui && docker pull ghcr.io/mhsanaei/3x-ui:latest && docker compose up -d 3xui

docker ps               # список контейнеров
docker system prune -a  # очистка всех неиспользуемых данных Docker
docker volume ls        # список томов

watch -n 1 'ss -Htn state established | wc -l' #количество активных TCP-подключений
```

## Благодарности

- [Akiyamov](https://github.com/Akiyamov/xray-vps-setup)
- [MHSanaei](https://github.com/MHSanaei/3x-ui)
- [API 3x-ui](https://documenter.getpostman.com/view/5146551/2sBXwnsBko)
- [NotDev](https://github.com/EikeiDev/vless-xtls-converter)
- [lxhao61](https://github.com/lxhao61/integrated-examples)
- [Xray-core v26.6.1](https://github.com/XTLS/Xray-core/releases/tag/v26.6.1)
