# 3x-ui + Caddy + VLESS Encryption + XTLS Vision + XHTTP

XHTTP-only схема для 3x-ui: публичный TLS завершает Caddy, трафик до Xray идёт через Unix Domain Socket `@uds_xhttp`, а новые установки по умолчанию включают **VLESS Encryption** и client `flow: "xtls-rprx-vision"`.

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

- **Единый inbound:** Создаётся только `VLESS-XHTTP-Backend` (`network: "xhttp"`, `security: "none"`, UDS/h2c). Публичный TLS завершает Caddy.
- **VLESS Encryption по умолчанию:** `setup.sh` после логина вызывает нативный API 3x-ui `GET /panel/api/server/getNewVlessEnc` и сохраняет пару в inbound settings: `settings.decryption` для сервера и `settings.encryption` для подписок/клиентов.
- **XTLS Vision для клиентов:** начальный клиент получает `flow: "xtls-rprx-vision"`; этот flow оптимизирует слой VLESS Encryption, а не транспорт XHTTP.
- **Безопасность панели:** Настраивает Basic Auth для панели через Caddy, скрывая ее за случайным путем.
- **Управление подписками:** Подписка XHTTP с одним UUID для всех клиентов. Автоматически включаются VLESS, JSON и Clash/Mihomo форматы.

### Требования

- Серверная часть рассчитана на **3x-ui v3.4.0** и **Xray-core v26.6.22**. Нужен Xray-core с поддержкой `vlessenc`; в этом проекте предполагается указанная связка версий.
- Клиент должен поддерживать одновременно **VLESS Encryption**, **XHTTP** и **XTLS Vision** (`flow: xtls-rprx-vision`).
- Расширенная XHTTP-обфускация всё ещё рассчитана на клиентов **Xray-core v26.6.1+**, но базовая совместимость проекта теперь — клиенты, совместимые с VLESS Encryption.

Для распространения конфигурации используется обычная VLESS-подписка 3x-ui.

В VLESS URI параметры `path`, `host` и `mode` передаются отдельно, `xPaddingBytes` дополнительно доступен как `x_padding_bytes`, а полный набор клиентских XHTTP-полей находится в URL-кодированном JSON-параметре `extra`.

## Слои трафика

```
VLESS user + flow=xtls-rprx-vision
        ↓
VLESS Encryption (settings.encryption/decryption)
        ↓
XHTTP transport (mode=stream-up, xmux)
        ↓
Caddy TLS / публичная сеть :443
```

Vision здесь относится к VLESS Encryption: он задаётся в объекте клиента как `flow`, но не превращает XHTTP в Vision-транспорт. За Caddy TLS termination и XHTTP/UDS не ожидается TCP splice — это нормальная схема для данного проекта.

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
| `scMaxEachPostBytes` | Оба | packet-up | Max Upload Size (Byte) | Макс. объём данных в одном POST. Default: 1000000 (1 МБ). Сервер отклоняет POST > лимита; клиент ограничивает размер. Диапазон `"100000-500000"` снижает фингерпринт |
| `scMinPostsIntervalMs` | Клиент | packet-up | Min upload interval (ms) | Мин. интервал между POST. Default: 30 мс — **DPI-фингерпринт!** Используйте `"50-150"` |
| `scMaxBufferedPosts` | Сервер | packet-up, stream-up | Max Buffered Upload | Макс. буферизованных POST на соединение. Default: 30. Используется в packet-up и stream-up |
| `scStreamUpServerSecs` | Сервер | stream-up | Stream-Up Server | Keepalive padding в stream-up (default: `"20-80"`) |
| `serverMaxHeaderBytes` | Сервер | Все | Server Max Header Bytes | Лимит размера заголовков (default: 8192) |
| `noSSEHeader` | Сервер | Все | No SSE Header | Подавляет SSE-заголовок в ответе |
| `uplinkHTTPMethod` | Клиент | Все | Uplink HTTP Method | HTTP-метод для загрузки: `POST`, `PUT`, `GET` (только packet-up) |
| `sessionPlacement` | Оба | packet-up, stream-up | Session Placement | Размещение session ID: `path`, `header`, `cookie`, `query`. Не используется в stream-one |
| `sessionKey` | Оба | packet-up, stream-up | Session Key | Имя ключа session (если placement ≠ path) |
| `seqPlacement` | Оба | packet-up | Sequence Placement | Размещение sequence number: `path`, `header`, `cookie`, `query` |
| `seqKey` | Оба | packet-up | Sequence Key | Имя ключа sequence (если placement ≠ path) |
| `uplinkDataPlacement` | Клиент | packet-up | Uplink Data Placement | Размещение данных upload: `body`, `header`, `cookie`, `query` |
| `uplinkDataKey` | Клиент | packet-up | Uplink Data Key | Имя ключа данных (если placement ≠ body) |
| `uplinkChunkSize` | Клиент | packet-up | Uplink Chunk Size | Размер чанка при размещении в header/cookie |
| `noGRPCHeader` | Клиент | stream-up, stream-one | No gRPC Header | Подавляет маскировку под gRPC |
| `xmux` | Клиент | packet-up, stream-up | XMUX (toggle) | Мультиплексирование H2/H3. Критично заполнять все ключевые поля (см. ниже) |
| `downloadSettings` | Клиент | stream-up | — (не в UI) | Разделение upstream/downstream |
| `headers` | Клиент | Все | Headers | Произвольные заголовки запроса |

> ⚠️ **`mode: "auto"` на клиенте** (dialer.go:361-369): auto разрешается по наличию REALITY, а не TLS. Без REALITY → `packet-up`. С REALITY без downloadSettings → `stream-one`. С REALITY + downloadSettings → `stream-up`. Серверный `auto` принимает все три режима. Мы используем явный `stream-up` на сервере, чтобы избежать путаницы.

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
Клиент
  VLESS UUID + flow=xtls-rprx-vision
  VLESS Encryption: settings.encryption из подписки
  XHTTP: mode=stream-up, xmux
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
│  settings.decryption = server vlessenc        │
│  settings.encryption = client/sub vlessenc    │
│  streamSettings.sockopt:                     │
│    acceptProxyProtocol: true                  │
│  listen: @uds_xhttp  (Unix Domain Socket)    │
│  network: xhttp, mode: stream-up              │
│  security: none  (TLS уже завершён в Caddy)    │
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

### Добавление клиентов и VLESS Encryption

`./setup.sh add-client` читает существующий inbound `VLESS-XHTTP-Backend`. Если в нём одновременно заполнены `settings.encryption` и `settings.decryption` и они не равны `none`, новый клиент получает только `flow: "xtls-rprx-vision"`.

В объекте клиента для `/panel/api/clients/add` поля `encryption` нет: строка VLESS Encryption хранится на уровне inbound и попадает в подписки из `settings.encryption`. Проверить состояние можно через `./setup.sh status` — для inbound будет показано `vlessenc=on`.

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
- [Параметры транспортного уровня xhttp](https://wiki.metacubex.one/ru/config/proxies/transport/#xhttp-opts)
