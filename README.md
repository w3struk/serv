# 3x-ui + Caddy + VLESS + XHTTP + TLS — полная схема проксирования

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

Скрипт полностью интерактивный. При запуске он запросит домен, предпочтительные логин/пароль для панели и режим работы с подписками.

```bash
cd /opt && git clone https://github.com/w3struk/serv && cd /serv

./setup.sh
```

> [!NOTE]
> Скрипт запускается от root, так как настраивает BBR и firewall.

### Возможности 

- **Создание Inbound'ов:** XHTTP + XTLS-Vision + TLS
- **Безопасность панели:** Настраивает Basic Auth для панели через Caddy, скрывая ее за случайным путем.
- **Управление подписками:** Поддерживает два режима генерации подписок на выбор (одна общая ссылка для обоих протоколов или раздельные ссылки).

## Архитектура проксирования

```
Клиент (VLESS/XHTTP)
       │
       │ TLS :443
       ▼
┌────────────────────────────────────────┐
│ 3x-ui  VLESS-TCP-Vision  (inbound 443) │
│  settings.fallbacks:                   │
│    [{dest: "@caddy_fallback", xver: 2}]│
└────────────────────────────────────────┘
       │ PROXY v2 (real client IP)
       ▼
┌────────────────────────────────────────┐
│ Caddy  :8080  bind unix/@caddy_fallback│
│   /admin-vkl8/* → 3x-ui panel :2053    │
│   /sub-t40c/*   → subconverter :2096   │
│   /api/v592/*   → XHTTP  (h2c+PROXYv2) │
└────────────────────────────────────────┘
       │ PROXY v2 (real client IP)
       ▼
┌────────────────────────────────────────┐
│ 3x-ui  VLESS-XHTTP-Backend             │
│  streamSettings.sockopt:               │
│    acceptProxyProtocol: true           │
│  listen: @uds_xhttp  (UDS, h2c)        │
└────────────────────────────────────────┘
```

### Цепочка обработки реального IP-адреса клиента

1. **Клиент → 3x-ui Vision (TLS :443):** прямой TCP, source IP сохраняется.
2. **Vision fallback → Caddy (`@caddy_fallback`):** Xray отправляет PROXY v2 header с реальным IP клиента (т.к. `xver: 2`); Caddy принимает через `listener_wrappers { proxy_protocol }`, `remote` = реальный IP.
3. **Caddy → XHTTP (`@uds_xhttp`):** Caddy **prepends** PROXY v2 header на исходящее UDS-соединение (через `transport http { proxy_protocol v2 }`).
4. **XHTTP Backend:** слушает UDS через `proxyproto.Listener(Policy: REQUIRE)`. Принимает PROXY v2 и устанавливает `net.Conn.RemoteAddr()` = реальный IP клиента. Параметр `sockopt.acceptProxyProtocol: true` активирует эту обёртку на уровне системного слушателя.
5. **Преимущества PROXY v2 над X-Forwarded-For:**
   - Не нужен `trustedXForwardedFor` (нет путаницы header name vs IP).
   - Не срабатывает `SECURITY WARNING: ... THIS IS VERY INSECURE!!!`.
   - Клиент не может подделать IP — PROXY v2 вставляется только Caddy'ом.
   - Реальный IP доступен на уровне соединения, а не через парсинг HTTP-заголовка.
6. **3x-ui лог (`/var/log/x-ui/3xipl.log`):** содержит реальный IP клиента, что позволяет корректно работать fail2ban.

## Управление и Полезные команды

Скрипт `setup.sh` предоставляет несколько встроенных команд:

```bash
./setup.sh              # Первоначальная установка (интерактивный режим)
./setup.sh add-client   # Добавление нового клиента к существующей установке
./setup.sh status       # Просмотр статуса контейнеров, ссылок, путей и портов
./setup.sh help         # Справка по командами скрипта
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

- [DeduskaPikhto](https://github.com/DeduskaPikhto/3x-ui-setup)
- [Akiyamov](https://github.com/Akiyamov/xray-vps-setup)
- [MHSanaei](https://github.com/MHSanaei/3x-ui)
- [NotDev](https://github.com/EikeiDev/vless-xtls-converter)
- [lxhao61](https://github.com/lxhao61/integrated-examples)
- https://github.com/MetaCubeX/mihomo/discussions/2669
- [API 3x-ui](https://documenter.getpostman.com/view/5146551/2sBXwnsBko)
