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
- **Управление подписками:** Подписка XHTTP с одним UUID для всех клиентов. Автоматически включаются VLESS, JSON и Clash/Mihomo форматы.

### Требования к Xray-клиенту

Расширенная XHTTP-обфускация рассчитана на **Xray-core v26.6.1**. Для распространения конфигурации используется обычная VLESS-подписка 3x-ui

В VLESS URI параметры `path`, `host` и `mode` передаются отдельно, `xPaddingBytes` дополнительно доступен как `x_padding_bytes`, а полный набор клиентских XHTTP-полей находится в URL-кодированном JSON-параметре `extra`.

## Параметры XHTTP: сервер vs клиент

3x-ui хранит все параметры XHTTP в inbound для передачи клиентам через подписки. `StripInboundXhttpClientFields` вырезает клиентские поля перед отправкой в xray-core runtime — сервер их не видит, но подписки их получают.

| Параметр | Сторона | Режимы | 3x-ui UI | Описание |
|---|---|---|---|---|
| `path`, `host`, `mode` | Оба | Все | Path, Host, Mode | Сервер проверяет, клиент отправляет |
| `xPaddingBytes` | Оба | Все | Padding Bytes | Размер случайного padding (диапазон, default: `"100-1000"`) |
| `xPaddingObfsMode` | Оба | Все | Padding Obfs Mode | Включает обфускацию padding (bool) |
| `xPaddingKey` | Оба | Все | Padding Key | Ключ обфускации (при включённом obfsMode) |
| `xPaddingHeader` | Оба | Все | Padding Header | Имя заголовка для padding |
| `xPaddingPlacement` | Оба | Все | Padding Placement | Размещение padding: `queryInHeader`, `header`, `cookie`, `query` |
| `xPaddingMethod` | Оба | Все | Padding Method | Метод обфускации: `repeat-x`, `tokenish` |
| `scMaxEachPostBytes` | Оба | Все | Max Upload Size (Byte) | Макс. объём данных в одном POST. Default: 1000000 (1 МБ). Диапазон `"100000-500000"` снижает фингерпринт |
| `scMinPostsIntervalMs` | Клиент | packet-up, auto | Min upload interval (ms) | Мин. интервал между POST. Default: 30 мс — **DPI-фингерпринт!** Используйте `"50-150"` |
| `scMaxBufferedPosts` | Сервер | packet-up, auto | Max Buffered Upload | Макс. буферизованных POST на соединение. Default: 30 |
| `scStreamUpServerSecs` | Сервер | stream-up | Stream-Up Server | Keepalive padding в stream-up (default: `"20-80"`) |
| `serverMaxHeaderBytes` | Сервер | Все | Server Max Header Bytes | Лимит размера заголовков (default: 8192) |
| `noSSEHeader` | Сервер | Все | No SSE Header | Подавляет SSE-заголовок в ответе |
| `uplinkHTTPMethod` | Клиент | Все | Uplink HTTP Method | HTTP-метод для загрузки: `POST`, `PUT`, `GET` (только packet-up) |
| `sessionPlacement` | Оба | Все | Session Placement | Размещение session ID: `path`, `header`, `cookie`, `query` |
| `sessionKey` | Оба | Все | Session Key | Имя ключа session (если placement ≠ path) |
| `seqPlacement` | Оба | Все | Sequence Placement | Размещение sequence number: `path`, `header`, `cookie`, `query` |
| `seqKey` | Оба | Все | Sequence Key | Имя ключа sequence (если placement ≠ path) |
| `uplinkDataPlacement` | Клиент | packet-up, auto | Uplink Data Placement | Размещение данных upload: `body`, `header`, `cookie`, `query` |
| `uplinkDataKey` | Клиент | packet-up, auto | Uplink Data Key | Имя ключа данных (если placement ≠ body) |
| `uplinkChunkSize` | Клиент | packet-up, auto | Uplink Chunk Size | Размер чанка при размещении в header/cookie |
| `noGRPCHeader` | Клиент | stream-up, stream-one | No gRPC Header | Подавляет маскировку под gRPC |
| `xmux` | Клиент | Все | XMUX (toggle) | Мультиплексирование H2/H3. Критично заполнять все ключевые поля (см. ниже) |
| `downloadSettings` | Клиент | stream-up | — (не в UI) | Разделение upstream/downstream |
| `headers` | Клиент | Все | Headers | Произвольные заголовки запроса |

> ⚠️ **`mode: "auto"` на клиенте:** при TLS-соединении auto разрешается в `packet-up` (а не в `stream-up`, как утверждается в документации xray). При REALITY — в `stream-one`. Серверный `auto` принимает все три режима. Мы используем явный `stream-up` на сервере, чтобы избежать путаницы.

### XMUX: критическое правило заполнения

Если заполнен **хотя бы один** параметр xmux — остальные теряют дефолты и становятся 0 (безлимит). Всегда заполняйте все три ключевых поля:

| Поле | Значение | Описание |
|---|---|---|
| `maxConcurrency` | `"16-32"` | Макс. одновременных запросов на соединение |
| `hMaxRequestTimes` | `"600-900"` | Макс. HTTP-запросов на соединение (Nginx default: 1000) |
| `hMaxReusableSecs` | `"1800-3000"` | Макс. время жизни соединения (Nginx default: 3600с) |

> ⚠️ **Не включайте `mux.cool` вместе с XHTTP.** При наличии `xmux` в inbound глобальный `subJsonMux` автоматически подавляется в JSON-подписках.

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
│   /json-xxxx/*  → 3x-ui sub service :2096    │
│   /clash-xxxx/* → 3x-ui sub service :2096    │
│   /api/vXXX/*   → XHTTP  (h2c+PROXYv2, UDS)  │
└─────────────────────┬────────────────────────┘
                      │ PROXY v2 (real client IP)
                      ▼
┌──────────────────────────────────────────────┐
│ 3x-ui  VLESS-XHTTP-Backend (inbound only)    │
│  streamSettings.sockopt:                     │
│    acceptProxyProtocol: true                  │
│  listen: @uds_xhttp  (Unix Domain Socket)    │
│  network: xhttp, mode: stream-up              │
│  xmux: maxConcurrency=16-32, hMaxReq=600-900  │
│        hMaxReusableSecs=1800-3000             │
└──────────────────────────────────────────────┘
```

## Управление и Полезные команды

Скрипт `setup.sh` предоставляет несколько встроенных команд:

```bash
./setup.sh                  # Первоначальная установка (интерактивный режим)
./setup.sh add-client       # Добавление нового клиента к существующей установке
./setup.sh status           # Просмотр статуса контейнеров, ссылок, путей и портов
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
- [lxhao61](https://github.com/lxhao61/integrated-examples)
- [Xray-core](https://github.com/XTLS/Xray-core)
- [NotDev](https://github.com/EikeiDev/vless-xtls-converter)
- [Some examples of uses for Xray-core ](https://github.com/XTLS/Xray-examples)
- [Browser Dialer](https://xtls.github.io/en/config/features/browser_dialer.html)
- [Xray Checker](https://xray-checker.kutovoy.dev/ru/)
