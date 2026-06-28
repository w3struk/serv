# 3x-ui + Caddy + VLESS Encryption + XTLS Vision + XHTTP

Готовая схема для 3x-ui с XHTTP: Caddy принимает HTTPS на `:443`, завершает TLS и передаёт XHTTP-трафик в Xray через Unix Domain Socket `@uds_xhttp`. При установке создаётся один inbound, включается **VLESS Encryption**, а первый клиент получает `flow: "xtls-rprx-vision"`.

## Быстрый старт

1. Подготовьте VPS и домен, который указывает на этот сервер.
2. Установите Docker, если он ещё не установлен.
3. Запустите установщик от `root`:

```bash
bash <(curl -sL https://raw.githubusercontent.com/w3struk/serv/main/setup.sh)
```

Или через `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/w3struk/serv/main/setup.sh)
```

Установщик интерактивный: он спросит домен, логин и пароль для панели. Репозиторий будет автоматически склонирован в `/opt/serv`, после чего будут запущены нужные сервисы.

> [!NOTE]
> Скрипт нужно запускать от `root`, потому что он настраивает BBR и firewall.

После установки перейдите в `/opt/serv` и используйте команды управления:

```bash
cd /opt/serv

./setup.sh status           # статус контейнеров, ссылки, пути и порты
./setup.sh add-client       # добавить нового клиента
./setup.sh help             # справка по командам скрипта
```

## Требования

- Зарегистрированный и делегированный домен, например `mydomain.com`, который указывает на ваш VPS.
- VPS с root-доступом.
- Docker и Docker Compose.
- Серверная часть рассчитана на **3x-ui v3.4.0** и **Xray-core v26.6.22** (с поддержкой `vlessenc`).
- Клиент должен быть совместим с **Xray-core v26.6.22** и поддерживать:
  - **VLESS Encryption**;
  - **XHTTP**;
  - **XTLS Vision** (`flow: xtls-rprx-vision`);
  - поля XHTTP `sessionIDTable` и `sessionIDLength`.


## Установка

### 1. Подготовьте SSH-доступ

Если сервер уже настроен и вход по ключу работает, этот шаг можно пропустить.

<details>
<summary>Настройка SSH</summary>

#### Генерация ключа

```bash
ssh-keygen -t ed25519
```

При выполнении команда предложит изменить место хранения ключа и добавить пароль. Путь можно оставить стандартным, пароль лучше добавить для безопасности.

#### Копирование публичного ключа на VPS

**Linux:**

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub ваш_пользователь@ваша_vps
```

**Windows PowerShell:**

```powershell
ssh-copy-id -i $env:USERPROFILE\.ssh\id_ed25519.pub ваш_пользователь@ваша_vps
```

Если `ssh-copy-id` не работает на Windows:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ваш_пользователь@ваша_vps "cat >> .ssh/authorized_keys"
```

#### Отключение входа по паролю

Создайте файл конфигурации:

```bash
sudo nano /etc/ssh/sshd_config.d/00-disable-password.conf
```

Добавьте:

```text
Port 22
PasswordAuthentication no
```

Перезапустите SSH:

```bash
sudo systemctl restart ssh
```

</details>

### 2. Установите Docker

Официальная инструкция: <https://docs.docker.com/engine/install/>

<details>
<summary>Быстрая установка Docker</summary>

```bash
bash <(wget -qO- https://get.docker.com)
```

#### Запуск Docker без root

```bash
sudo usermod -aG docker $USER
newgrp docker
```

</details>

### 3. Запустите установщик

```bash
bash <(curl -sL https://raw.githubusercontent.com/w3struk/serv/main/setup.sh)
```

Или:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/w3struk/serv/main/setup.sh)
```

Что делает установщик:

- создаёт единый inbound `VLESS-XHTTP-Backend`;
- настраивает XHTTP: `network: "xhttp"`, `security: "none"`, UDS/h2c;
- завершает публичный TLS в Caddy;
- включает VLESS Encryption через API 3x-ui;
- создаёт первого клиента с `flow: "xtls-rprx-vision"`;
- включает подписки VLESS, JSON и Clash/Mihomo;
- закрывает доступ к панели через Caddy Basic Auth и случайный путь.

## Управление

Команды выполняются из каталога `/opt/serv`:

```bash
./setup.sh                  # первоначальная установка, интерактивный режим
./setup.sh add-client       # добавление нового клиента к существующей установке
./setup.sh status           # просмотр статуса контейнеров, ссылок, путей и портов
./setup.sh help             # справка по командам скрипта
```

Для inbound будет показано `vlessenc=on`.

### Docker-команды

<details>
<summary>Полезные команды Docker</summary>

```bash
# Перезапуск всех сервисов и просмотр логов
docker compose down && docker compose up -d && docker compose logs -f

# Обновление 3x-ui до последней версии
docker compose down 3xui && docker pull ghcr.io/mhsanaei/3x-ui:latest && docker compose up -d 3xui

docker ps               # список контейнеров
docker system prune -a  # очистка всех неиспользуемых данных Docker
docker volume ls        # список томов

watch -n 1 'ss -Htn state established | wc -l' # количество активных TCP-подключений
```

</details>

## Технические детали / Advanced

### Основные свойства конфигурации

- **Единый inbound:** создаётся только `VLESS-XHTTP-Backend` (`network: "xhttp"`, `security: "none"`, UDS/h2c). Публичный TLS завершает Caddy.
- **VLESS Encryption по умолчанию:** `setup.sh` после логина вызывает нативный API 3x-ui `GET /panel/api/server/getNewVlessEnc` и сохраняет пару в inbound settings: `settings.decryption` для сервера и `settings.encryption` для подписок и клиентов.
- **XTLS Vision для клиентов:** начальный клиент получает `flow: "xtls-rprx-vision"`. Этот flow оптимизирует слой VLESS Encryption, а не транспорт XHTTP.
- **Безопасность панели:** Caddy закрывает панель Basic Auth и случайным путём.
- **Подписки:** глобально включаются endpoints и форматы VLESS, JSON и Clash/Mihomo. У каждого клиента свой UUID и URL подписки по `subId`.

Для распространения конфигурации используется обычная VLESS-подписка 3x-ui.

В VLESS URI параметры `path`, `host` и `mode` передаются отдельно, `xPaddingBytes` дополнительно доступен как `x_padding_bytes`, а полный набор клиентских XHTTP-полей находится в URL-кодированном JSON-параметре `extra`.

### Слои трафика

```text
VLESS user + flow=xtls-rprx-vision
        ↓
VLESS Encryption (settings.encryption/decryption)
        ↓
XHTTP transport (mode=stream-up, xmux)
        ↓
Caddy TLS / публичная сеть :443
```

За Caddy TLS termination и XHTTP/UDS не ожидается TCP splice — это нормальная схема для данного проекта.

### Важные предупреждения

> ⚠️ **`mode: "auto"` на клиенте** (`dialer.go:361-369`): `auto` разрешается по наличию REALITY, а не TLS. Без REALITY → `packet-up`. С REALITY без `downloadSettings` → `stream-one`. С REALITY + `downloadSettings` → `stream-up`. Серверный `auto` принимает все три режима. В этом проекте используется явный `stream-up` на сервере, чтобы избежать путаницы.

> ⚠️ **Не включайте `mux.cool` вместе с XHTTP.** При наличии `xmux` в inbound глобальный `subJsonMux` автоматически подавляется в JSON-подписках.

### XMUX: профиль Xray-core v26.6.27

`setup.sh` явно задаёт все шесть полей `xmux`, чтобы подписки не зависели от неявных дефолтов клиента. Профиль соответствует Xray-core v26.6.27 default anti-RKN:

| Поле | Значение | Описание |
|---|---|---|
| `maxConcurrency` | `0` | Не включает лимит одновременных запросов на соединение |
| `maxConnections` | `"6"` | Новое default-значение Xray-core v26.6.27 |
| `cMaxReuseTimes` | `0` | Не задаёт клиентский лимит переиспользований соединения |
| `hMaxRequestTimes` | `"600-900"` | Максимум HTTP-запросов на соединение (Nginx default: 1000) |
| `hMaxReusableSecs` | `"1800-3000"` | Максимальное время жизни соединения (Nginx default: 3600с) |
| `hKeepAlivePeriod` | `0` | Явное нулевое значение keepalive period |

## Архитектура

`$XHTTP_PATH` — путь XHTTP, который генерирует установщик. В текущем `setup.sh` это значение вида `api/vN`, поэтому публичный маршрут выглядит как `/api/vN/*`.

```text
Клиент
  VLESS UUID + flow=xtls-rprx-vision
  VLESS Encryption: settings.encryption из подписки
  XHTTP: mode=stream-up, xmux
       │
       │ TLS :443, /$XHTTP_PATH/*
       ▼
┌──────────────────────────────────────────────┐
│ Caddy  (public TLS termination)              │
│   /admin-xxxx/* → 3x-ui panel      :2053     │
│   /sub-xxxx/*   → 3x-ui sub service :2096    │
│   /json-xxxx/*  → 3x-ui sub service :2096    │
│   /clash-xxxx/* → 3x-ui sub service :2096    │
│   /$XHTTP_PATH/* → Xray XHTTP over UDS       │
└─────────────────────┬────────────────────────┘
                      │ PROXY v2 (real client IP)
                      ▼
┌──────────────────────────────────────────────┐
│ Xray inbound VLESS-XHTTP-Backend             │
│  settings.decryption = server vlessenc       │
│  settings.encryption = client/sub vlessenc   │
│  streamSettings.sockopt:                     │
│    acceptProxyProtocol: true                 │
│  listen: @uds_xhttp  (Unix Domain Socket)    │
│  network: xhttp, mode: stream-up             │
│  security: none  (TLS уже завершён в Caddy)  │
│  xmux: six explicit fields                   │
└──────────────────────────────────────────────┘
```

Вне `xhttpSettings` установщик задаёт:

- `network: "xhttp"`;
- UDS `@uds_xhttp`;
- `security: "none"`;
- `sockopt.acceptProxyProtocol: true`;
- `sockopt.trustedXForwardedFor: ["127.0.0.1/32"]`;
- в Caddy — h2c + PROXY v2.

## Справочник XHTTP

3x-ui хранит все параметры XHTTP в inbound, чтобы передавать их клиентам через подписки. `StripInboundXhttpClientFields` вырезает клиентские поля перед отправкой в xray-core runtime: сервер их не видит, но подписки их получают.

Легенда: `нет` в колонке `setup.sh` означает «не задаёт установщик», а не «не поддерживается».

<details>
<summary>Параметры XHTTP: сервер и клиент</summary>

| Параметр | Сторона | Режимы | 3x-ui UI | setup.sh | Описание |
|---|---|---|---|---|---|
| `path` | Оба | Все | Path | да: `/$XHTTP_PATH` | Сервер проверяет, клиент отправляет |
| `host` | Оба | Все | Host | нет в `xhttpSettings`; Host row: address/SNI/port/TLS/fingerprint | Публичный host для подписок задаётся через Host row |
| `mode` | Оба | Все | Mode | да: `stream-up` | Режим XHTTP |
| `xPaddingBytes` | Оба | Все | Padding Bytes | да: `100-1000` | Размер случайного padding (диапазон, default: `"100-1000"`) |
| `xPaddingObfsMode` | Оба | Все | Padding Obfs Mode | опц.: `true` | Включает обфускацию padding (bool) |
| `xPaddingKey` | Оба | Все | Padding Key | опц.: `trace` | Ключ обфускации при включённом obfsMode |
| `xPaddingHeader` | Оба | Все | Padding Header | опц.: `X-Trace-ID` | Имя заголовка для padding |
| `xPaddingPlacement` | Оба | Все | Padding Placement | опц.: `queryInHeader` | Размещение padding: `queryInHeader`, `header`, `cookie`, `query` |
| `xPaddingMethod` | Оба | Все | Padding Method | опц.: `tokenish` | Метод обфускации: `repeat-x`, `tokenish` |
| `scMaxEachPostBytes` | Оба | packet-up | Max Upload Size (Byte) | нет | Максимальный объём данных в одном POST. Default: 1000000 (1 МБ). Сервер отклоняет POST > лимита; клиент ограничивает размер. Диапазон `"100000-500000"` снижает фингерпринт |
| `scMinPostsIntervalMs` | Клиент | packet-up | Min upload interval (ms) | нет | Минимальный интервал между POST. Default: 30 мс — **DPI-фингерпринт!** Используйте `"50-150"` |
| `scMaxBufferedPosts` | Сервер | packet-up, stream-up | Max Buffered Upload | да: `30` | Максимум буферизованных POST на соединение. Default: 30. Используется в packet-up и stream-up |
| `scStreamUpServerSecs` | Сервер | stream-up | Stream-Up Server | да: `20-80` | Keepalive padding в stream-up (default: `"20-80"`) |
| `serverMaxHeaderBytes` | Сервер | Все | Server Max Header Bytes | опц.: `16384` при advanced obfs | Лимит размера заголовков (default: 8192) |
| `noSSEHeader` | Сервер | Все | No SSE Header | нет | Подавляет SSE-заголовок в ответе |
| `uplinkHTTPMethod` | Клиент | Все | Uplink HTTP Method | нет | HTTP-метод для загрузки: `POST`, `PUT`, `GET` (только packet-up) |
| `sessionIDPlacement` | Оба | packet-up, stream-up | Session ID Placement | нет | Размещение session ID: `path`, `header`, `cookie`, `query`. Не используется в stream-one |
| `sessionIDKey` | Оба | packet-up, stream-up | Session ID Key | нет | Имя ключа session ID, если placement ≠ path |
| `sessionIDTable` | Оба | packet-up, stream-up | Session ID Table | да: `Base62` | Алфавит session ID |
| `sessionIDLength` | Оба | packet-up, stream-up | Session ID Length | да: `16-32` | Длина session ID |
| `seqPlacement` | Оба | packet-up | Sequence Placement | нет | Размещение sequence number: `path`, `header`, `cookie`, `query` |
| `seqKey` | Оба | packet-up | Sequence Key | нет | Имя ключа sequence, если placement ≠ path |
| `uplinkDataPlacement` | Клиент | packet-up | Uplink Data Placement | нет | Размещение данных upload: `body`, `header`, `cookie`, `query` |
| `uplinkDataKey` | Клиент | packet-up | Uplink Data Key | нет | Имя ключа данных, если placement ≠ body |
| `uplinkChunkSize` | Клиент | packet-up | Uplink Chunk Size | нет | Размер чанка при размещении в header/cookie |
| `noGRPCHeader` | Клиент | stream-up, stream-one | No gRPC Header | нет | Подавляет маскировку под gRPC |
| `xmux` | Клиент | packet-up, stream-up | XMUX (toggle) | да: `maxConcurrency=0`; `maxConnections=6`; `cMaxReuseTimes=0`; `hMaxRequestTimes=600-900`; `hMaxReusableSecs=1800-3000`; `hKeepAlivePeriod=0` | Мультиплексирование H2/H3. Соответствует Xray-core v26.6.27 default anti-RKN |
| `downloadSettings` | Клиент | stream-up | — (не в UI) | нет | Разделение upstream/downstream |
| `headers` | Клиент | Все | Headers | частично: `User-Agent=chrome`; остальное — нет | Произвольные заголовки запроса |

</details>

`sessionIDPlacement` и `sessionIDKey` намеренно не задаются: установщик оставляет default-размещение в path и меняет только таблицу и длину session ID.

## Благодарности

- [Akiyamov](https://github.com/Akiyamov/xray-vps-setup)
- [MHSanaei](https://github.com/MHSanaei/3x-ui)
- [API 3x-ui](https://documenter.getpostman.com/view/5146551/2sBXwnsBko)
- [lxhao61](https://github.com/lxhao61/integrated-examples)
- [Xray-core](https://github.com/XTLS/Xray-core)
- [NotDev](https://github.com/EikeiDev/vless-xtls-converter)
- [Some examples of uses for Xray-core](https://github.com/XTLS/Xray-examples)
- [Browser Dialer](https://xtls.github.io/en/config/features/browser_dialer.html)
- [Xray Checker](https://xray-checker.kutovoy.dev/ru/)
- [Параметры транспортного уровня xhttp](https://wiki.metacubex.one/ru/config/proxies/transport/#xhttp-opts)
