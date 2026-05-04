# tproxy.sh — Android Transparent Proxy Shell

> [RU](#ru-tproxysh) | [EN](#en-tproxysh)

---

## RU tproxy.sh

Модульный shell-скрипт для настройки **прозрачного прокси (TPROXY)** на **Android-устройствах с root-правами**.

### Основные возможности

- **Прозрачное прокси**: Режим TPROXY (сохраняет оригинальный IP и порт источника, поддерживает TCP + UDP)
- **Проксирование отдельных приложений**: Чёрный/белый список по именам пакетов или UID (поддержка многопользовательского режима в формате `userId:package`)
- **Управление сетевыми интерфейсами**: Независимое включение/выключение прокси для мобильных данных, Wi-Fi, точки доступа (хотспот), USB-модема и пользовательских интерфейсов
- **Фильтрация MAC-адресов точки доступа**: Чёрный/белый список для клиентов хотспота по MAC-адресу
- **Обход российских IP**: Автоматическая загрузка и обход списков RU IPv4/IPv6 через ipset
- **Полная поддержка IPv6**: Опциональные отдельные правила/метки/таблицы для IPv6
- **Перехват DNS**: Режим TPROXY на кастомный локальный порт DNS (защита от утечек)
- **Блокировка QUIC**: Опциональная блокировка протокола QUIC (UDP порт 443)
- **Пользовательские хуки (Hooks)**: Функции `pre_start_hook()` и `post_stop_hook()` — выполняются перед применением правил и после очистки
- **Автопроверка функций ядра**: Проверка необходимых модулей (`xt_TPROXY`, `xt_owner`, `xt_mac`, `ip_set` и др.)
- **Режим тестового запуска (Dry-run)**: Проверка конфигурации без применения изменений
- **Принудительный пропуск проверок ядра**: `SKIP_CHECK_FEATURE=1` для кастомных или старых ядер

### Требования

- Android с root-правами (Magisk / KernelSU / APatch)
- Команды `iptables` / `ip6tables` + `ip`
- Команда `curl` (для загрузки списков RU IP)
- Модули/функции ядра:
  - `xt_TPROXY` (обязательно для прозрачного прокси)
  - `xt_owner` (для разделения по приложениям)
  - `xt_mac` (для фильтрации по MAC)
  - `ip_set` + `xt_set` (для обхода RU IP)

> В стоковых ядрах Android часто отсутствуют некоторые модули (особенно `xt_set`, `xt_mac`). Для полной функциональности часто требуются кастомные ядра.

- Прокси-клиент, слушающий на localhost с поддержкой TPROXY (например, tproxy inbound в sing-box или dokodemo-door + sockopt tproxy в xray)

### Установка

```bash
curl https://raw.githubusercontent.com/w3struk/steal-oneself/main/client/tproxy/tproxy.sh -o /data/adb/tproxy.sh
chmod 755 /data/adb/tproxy.sh
```

или

```bash
adb push tproxy.sh /data/local/tmp/
adb shell chmod +x /data/local/tmp/tproxy.sh
```

### Использование

#### Приоритет загрузки конфигурации

1. **Переменные окружения**, переданные через командную строку (высший приоритет)
   ```bash
   PROXY_TCP_PORT=7893 PROXY_UDP_PORT=7893 BLOCK_QUIC=1 ./tproxy.sh start
   ```

2. **Файл `tproxy.conf`** в директории, указанной через `-d / --dir` (или в директории скрипта)

3. **Встроенные значения по умолчанию** в самом скрипте (низший приоритет)

#### Быстрый старт

```bash
# Обычный запуск (использует значения по умолчанию + tproxy.conf, если есть)
su -c "/data/adb/tproxy.sh start"

# С указанием директории конфигов (рекомендуется)
su -c "/data/adb/tproxy.sh -d /data/adb/ start"

# Переопределение портов + блокировка QUIC
su -c "PROXY_TCP_PORT=7893 PROXY_UDP_PORT=7893 BLOCK_QUIC=1 /data/adb/tproxy.sh -d /data/adb start"
```

#### Создание tproxy.conf (рекомендуется)

Создайте файл `tproxy.conf` в вашей директории конфигурации (например, `/data/adb/tproxy.conf`):

```bash
# Пример tproxy.conf
PROXY_TCP_PORT=7893
PROXY_UDP_PORT=7893
PROXY_MODE=1                # принудительно TPROXY
DNS_HIJACK_ENABLE=1
DNS_PORT=1053
BLOCK_QUIC=1                # блокировать QUIC
BYPASS_RU_IP=1
PROXY_IPV6=1
APP_PROXY_ENABLE=1
APP_PROXY_MODE=blacklist
BYPASS_APPS_LIST="0:com.android.systemui 10:com.tencent.mm"
```

#### Пользовательские хуки (Optional)

Две опциональные функции-хука в `tproxy.conf` (или прямо в скрипте):

- `pre_start_hook()` — выполняется **перед** применением правил (например, запуск прокси-ядра)
- `post_stop_hook()` — выполняется **после** очистки (например, остановка процесса прокси-ядра)

Пример в tproxy.conf:

```bash
pre_start_hook() {
    log Info "User pre-start: запуск прокси-ядра..."
    su -c "busybox setuidgid $CORE_USER_GROUP /path/to/proxy-binary ..."
    sleep 3
}

post_stop_hook() {
    log Info "User post-stop: очистка..."
    pkill -f clash
}
```

> Не определяйте функции с именами, конфликтующими со встроенными (`log`, `start_proxy`, `block_quic` и т.д.).

#### Полный список переменных конфигурации

| Опция | По умолчанию | Описание |
|-------|-------------|----------|
| `CORE_USER_GROUP` | `root:net_admin` | Пользователь и группа, от имени которых работает ядро |
| `ROUTING_MARK` | (пусто) | Опциональное значение fwmark для обхода трафика ядра |
| `FORCE_MARK_BYPASS` | `0` | Принудительное использование обхода по меткам (1 = принудительно) |
| `PROXY_TCP_PORT` / `PROXY_UDP_PORT` | `1536` | Порты, на которых слушает прозрачный прокси |
| `PROXY_MODE` | `1` | Режим прокси: 0 (авто), 1 (принудительно TPROXY) |
| `PERFORMANCE_MODE` | `0` | 0=обычный, 1=оптимизированный (conntrack, цепочка DIVERT) |
| `DNS_HIJACK_ENABLE` | `1` | Перехват DNS (0=выкл, 1=через TPROXY) |
| `DNS_PORT` | `1053` | Порт DNS-сервера прокси-клиента |
| `BYPASS_IPv4_LIST` | (стандартные private/reserved) | Диапазоны IPv4, всегда идущие в обход прокси |
| `BYPASS_IPv6_LIST` | (стандартные private/reserved) | Диапазоны IPv6, всегда идущие в обход прокси |
| `PROXY_IPv4_LIST` / `PROXY_IPv6_LIST` | (пусто) | Список IP-адресов, требующих проксирования |
| `HOTSPOT_SUBNET_IPV4` / `HOTSPOT_SUBNET_IPV6` | `192.168.43.0/24` / `fe80::/10` | Подсеть хотспота (только если хотспот и Wi-Fi делят один интерфейс) |
| `MOBILE_INTERFACE` | `rmnet_data+` | Имя интерфейса мобильных данных |
| `WIFI_INTERFACE` | `wlan0` | Имя интерфейса Wi-Fi |
| `HOTSPOT_INTERFACE` | `wlan2` | Имя интерфейса точки доступа |
| `USB_INTERFACE` | `rndis+` | Имя интерфейса USB-модема |
| `OTHER_BYPASS_INTERFACES` | (пусто) | Другие интерфейсы для обхода прокси (через пробел) |
| `OTHER_PROXY_INTERFACES` | (пусто) | Другие интерфейсы для проксирования (через пробел) |
| `PROXY_MOBILE` | `1` | Проксировать мобильные данные (1=да, 0=нет) |
| `PROXY_WIFI` | `1` | Проксировать Wi-Fi (1=да, 0=нет) |
| `PROXY_HOTSPOT` | `0` | Проксировать точку доступа (1=да, 0=нет) |
| `PROXY_USB` | `0` | Проксировать USB-модем (1=да, 0=нет) |
| `PROXY_TCP` / `PROXY_UDP` | `1` / `1` | Проксировать TCP/UDP (1=да, 0=нет) |
| `PROXY_IPV6` | `0` | 0=выкл прокси, 1=вкл прокси, -1=полностью отключить стек IPv6 |
| `APP_PROXY_ENABLE` | `0` | Включить проксирование отдельных приложений (1=да) |
| `APP_PROXY_MODE` | `blacklist` | `blacklist` (обход указанных) или `whitelist` (только указанные) |
| `BYPASS_APPS_LIST` / `PROXY_APPS_LIST` | (пусто) | Список приложений: `"userId:package.name"` |
| `BYPASS_RU_IP` | `0` | Обход российских IP (1=вкл, 0=выкл; требует `ipset`) |
| `BLOCK_QUIC` | `0` | Блокировать QUIC (UDP 443). С `BYPASS_RU_IP=1` — только нероссийские направления |
| `RU_IP_URL` / `RU_IPV6_URL` | (GitHub ipverse) | URL для загрузки списков российских IP |
| `MAC_FILTER_ENABLE` | `0` | Фильтрация по MAC-адресам (1=да; только при `PROXY_HOTSPOT=1`) |
| `MAC_PROXY_MODE` | `blacklist` | `blacklist` (обход) или `whitelist` (только указанные MAC) |
| `BYPASS_MACS_LIST` / `PROXY_MACS_LIST` | (пусто) | Список MAC-адресов (через пробел) |
| `MARK_VALUE` | `20` | Маркировка трафика для маршрутизации IPv4 |
| `MARK_VALUE6` | `25` | Маркировка трафика для маршрутизации IPv6 |
| `TABLE_ID` | `2025` | Номер кастомной таблицы маршрутизации ip rule/route |
| `LOG_TIMESTAMP` | `1` | Включить временные метки в логах (0=выкл, 1=вкл) |
| `SKIP_CHECK_FEATURE` | `0` | Пропустить проверки ядра (используйте с осторожностью) |

#### Параметры командной строки

```
Usage: tproxy.sh {start|stop|restart|status} [options]

Commands:
  start     Применить правила прокси, маршрутизацию, ipset, настройки sysctl
  stop      Удалить все добавленные правила, маршруты, ipset, восстановить sysctl
  restart   stop → небольшая пауза → start
  status    Показать текущие правила и маршруты (алиас: check)

Options:
  -d DIR, --dir DIR       Указать директорию конфигов
  --dry-run               Симуляция всех операций (без реальных изменений)
  --verbose               Показать подробные отладочные логи
  -v, --version           Показать версию
  -h, --help              Показать справку
```

#### Остановка

```bash
su -c "/data/adb/tproxy.sh stop"
su -c "/data/adb/tproxy.sh -d /data/adb stop"
```

#### Просмотр статуса

```bash
su -c "/data/adb/tproxy.sh status"

# Ручная проверка
su -c iptables -t mangle -vL
su -c iptables -t nat -nvL
su -c ip rule show
su -c ip route show table all | grep 2025
```

---

### Примеры настройки прокси-клиентов

> Прокси-ядро должно слушать на указанном порту (по умолчанию 1536) с поддержкой TPROXY. Обычно требует запуска от имени root или с правами `cap_net_admin`.

#### Запуск ядра на Android

**Использование busybox setuidgid:**
```bash
su -c "busybox setuidgid $CORE_USER_GROUP /path/to/proxy-binary ..."
```

**Для не-root пользователей (кастомный UID:GID):**
```bash
# Один раз, от root:
su -c "setcap cap_net_admin,cap_net_bind_service,cap_net_raw+eip /path/to/proxy-binary"

# Запуск:
su -c "busybox setuidgid $CORE_USER_GROUP /path/to/proxy-binary ..."
```

**Альтернатива через capsh:**
```bash
su -c "capsh --caps='cap_net_admin,cap_net_bind_service,cap_net_raw+eip' --addamb='cap_net_admin,cap_net_bind_service,cap_net_raw' --secbits=1 -- -c '/path/to/proxy-binary ...'"
```

#### Пример для sing-box

```json
{
  "dns": {
    "servers": [
      {
        "tag": "ali",
        "type": "https",
        "server": "223.6.6.6"
      }
    ],
    "independent_cache": true,
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tproxy",
      "tag": "tproxy_in",
      "listen": "::",
      "listen_port": 1536
    }
  ],
  "route": {
    "default_domain_resolver": "ali",
    "rules": [
      {
        "action": "sniff"
      },
      {
        "type": "logical",
        "mode": "or",
        "rules": [
          { "port": 53 },
          { "protocol": "dns" }
        ],
        "action": "hijack-dns"
      }
    ]
  }
}
```

#### Пример для Clash

```yaml
tproxy-port: 1536

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/15
  fake-ip-filter:
    - "*"
    - "+.lan"
    - "+.local"
  nameserver:
    - https://120.53.53.53/dns-query
    - https://223.5.5.5/dns-query
```

#### Пример для Clash Meta (mihomo)

```yaml
tproxy-port: 1536

proxies:
  - name: "DNS_Hijack"
    type: dns

rules:
  - DST-PORT,53,DNS_Hijack
```

#### Пример для xray / v2ray (dokodemo-door + tproxy)

```json
{
  "listen": "127.0.0.1",
  "port": 1536,
  "protocol": "dokodemo-door",
  "settings": {
    "network": "tcp,udp",
    "followRedirect": true
  },
  "streamSettings": {
    "sockopt": {
      "tproxy": "tproxy"
    }
  },
  "tag": "transparent-in"
}
```

---

## EN tproxy.sh

Modular shell script for setting up **transparent proxy (TPROXY)** on **rooted Android devices**.

### Features

- **Transparent proxy**: TPROXY mode (preserves original source IP and port, TCP + UDP)
- **Per-app proxy**: Blacklist/whitelist by package names or UIDs (multi-user `userId:package` format)
- **Network interface management**: Independent proxy toggle for mobile, Wi-Fi, hotspot, USB tethering, and custom interfaces
- **Hotspot MAC address filtering**: Blacklist/whitelist for hotspot clients by MAC address
- **Russian IP bypass**: Automatic download and bypass of RU IPv4/IPv6 lists via ipset
- **Full IPv6 support**: Optional separate rules/marks/tables for IPv6
- **DNS hijacking**: TPROXY mode on custom local DNS port (leak protection)
- **QUIC blocking**: Optional QUIC (UDP port 443) blocking via `BLOCK_QUIC=1`
- **User hooks**: `pre_start_hook()` and `post_stop_hook()` — executed before applying rules and after cleanup
- **Auto kernel feature check**: Checks for required modules (`xt_TPROXY`, `xt_owner`, `xt_mac`, `ip_set`, etc.)
- **Dry-run mode**: Test configuration without applying changes
- **Skip kernel checks**: `SKIP_CHECK_FEATURE=1` for custom or older kernels

### Requirements

- Android with root (Magisk / KernelSU / APatch)
- `iptables` / `ip6tables` + `ip` commands
- `curl` command (for downloading RU IP lists)
- Kernel modules: `xt_TPROXY`, `xt_owner`, `xt_mac`, `ip_set` + `xt_set`

> Stock Android kernels often lack some modules (especially `xt_set`, `xt_mac`). Custom kernels are often needed for full functionality.

- Proxy client listening on localhost with TPROXY support (e.g., sing-box tproxy inbound or xray dokodemo-door + sockopt tproxy)

### Installation

```bash
curl https://raw.githubusercontent.com/w3struk/steal-oneself/main/client/tproxy/tproxy.sh -o /data/adb/tproxy.sh
chmod 755 /data/adb/tproxy.sh
```

or

```bash
adb push tproxy.sh /data/local/tmp/
adb shell chmod +x /data/local/tmp/tproxy.sh
```

### Usage

#### Configuration Loading Priority

1. **Environment variables** passed via command line (highest priority)
   ```bash
   PROXY_TCP_PORT=7893 PROXY_UDP_PORT=7893 BLOCK_QUIC=1 ./tproxy.sh start
   ```

2. **`tproxy.conf` file** in directory specified via `-d / --dir` (or script directory)

3. **Built-in defaults** in the script itself (lowest priority)

#### Quick Start

```bash
# Normal launch (uses defaults + tproxy.conf if present)
su -c "/data/adb/tproxy.sh start"

# With config directory (recommended)
su -c "/data/adb/tproxy.sh -d /data/adb/ start"

# Override ports + block QUIC
su -c "PROXY_TCP_PORT=7893 PROXY_UDP_PORT=7893 BLOCK_QUIC=1 /data/adb/tproxy.sh -d /data/adb start"
```

#### Create tproxy.conf (recommended)

Create `tproxy.conf` in your config directory (e.g., `/data/adb/tproxy.conf`):

```bash
# Example tproxy.conf
PROXY_TCP_PORT=7893
PROXY_UDP_PORT=7893
PROXY_MODE=1                # force TPROXY
DNS_HIJACK_ENABLE=1
DNS_PORT=1053
BLOCK_QUIC=1                # block QUIC
BYPASS_RU_IP=1
PROXY_IPV6=1
APP_PROXY_ENABLE=1
APP_PROXY_MODE=blacklist
BYPASS_APPS_LIST="0:com.android.systemui 10:com.tencent.mm"
```

#### User Hooks (Optional)

Two optional hook functions in `tproxy.conf` (or directly in the script):

- `pre_start_hook()` — runs **before** applying rules (e.g., start proxy core)
- `post_stop_hook()` — runs **after** cleanup (e.g., stop proxy core process)

Example in tproxy.conf:

```bash
pre_start_hook() {
    log Info "User pre-start: starting proxy core..."
    su -c "busybox setuidgid $CORE_USER_GROUP /path/to/proxy-binary ..."
    sleep 3
}

post_stop_hook() {
    log Info "User post-stop: cleanup..."
    pkill -f clash
}
```

> Do not define functions with names conflicting with built-in ones (`log`, `start_proxy`, `block_quic`, etc.).

#### Full Configuration Variables

| Option | Default | Description |
|--------|---------|-------------|
| `CORE_USER_GROUP` | `root:net_admin` | User:group for the proxy core |
| `ROUTING_MARK` | (empty) | Optional fwmark for bypassing core traffic |
| `FORCE_MARK_BYPASS` | `0` | Force mark-based bypass (1 = force) |
| `PROXY_TCP_PORT` / `PROXY_UDP_PORT` | `1536` | Transparent proxy listening ports |
| `PROXY_MODE` | `1` | 0 (auto), 1 (force TPROXY) |
| `PERFORMANCE_MODE` | `0` | 0=normal, 1=optimized (conntrack, DIVERT chain) |
| `DNS_HIJACK_ENABLE` | `1` | DNS hijack (0=off, 1=via TPROXY) |
| `DNS_PORT` | `1053` | Proxy client DNS server port |
| `BYPASS_IPv4_LIST` | (standard private/reserved) | IPv4 ranges always bypassing proxy |
| `BYPASS_IPv6_LIST` | (standard private/reserved) | IPv6 ranges always bypassing proxy |
| `PROXY_IPv4_LIST` / `PROXY_IPv6_LIST` | (empty) | IP ranges that require proxying |
| `HOTSPOT_SUBNET_IPV4` / `HOTSPOT_SUBNET_IPV6` | `192.168.43.0/24` / `fe80::/10` | Hotspot subnet (only when hotspot and Wi-Fi share one interface) |
| `MOBILE_INTERFACE` | `rmnet_data+` | Mobile data interface name |
| `WIFI_INTERFACE` | `wlan0` | Wi-Fi interface name |
| `HOTSPOT_INTERFACE` | `wlan2` | Hotspot interface name |
| `USB_INTERFACE` | `rndis+` | USB tethering interface name |
| `OTHER_BYPASS_INTERFACES` | (empty) | Other interfaces to bypass (space-separated) |
| `OTHER_PROXY_INTERFACES` | (empty) | Other interfaces to proxy (space-separated) |
| `PROXY_MOBILE` | `1` | Proxy mobile data (1=yes, 0=no) |
| `PROXY_WIFI` | `1` | Proxy Wi-Fi (1=yes, 0=no) |
| `PROXY_HOTSPOT` | `0` | Proxy hotspot (1=yes, 0=no) |
| `PROXY_USB` | `0` | Proxy USB tethering (1=yes, 0=no) |
| `PROXY_TCP` / `PROXY_UDP` | `1` / `1` | Proxy TCP/UDP (1=yes, 0=no) |
| `PROXY_IPV6` | `0` | 0=proxy off, 1=proxy on, -1=fully disable IPv6 stack |
| `APP_PROXY_ENABLE` | `0` | Enable per-app proxy (1=yes) |
| `APP_PROXY_MODE` | `blacklist` | `blacklist` (bypass listed) or `whitelist` (only proxy listed) |
| `BYPASS_APPS_LIST` / `PROXY_APPS_LIST` | (empty) | App list: `"userId:package.name"` |
| `BYPASS_RU_IP` | `0` | Bypass Russian IPs (1=on, 0=off; requires `ipset`) |
| `BLOCK_QUIC` | `0` | Block QUIC (UDP 443). With `BYPASS_RU_IP=1` — only non-RU destinations |
| `RU_IP_URL` / `RU_IPV6_URL` | (GitHub ipverse) | URLs for downloading Russian IP lists |
| `MAC_FILTER_ENABLE` | `0` | MAC address filtering (1=yes; only with `PROXY_HOTSPOT=1`) |
| `MAC_PROXY_MODE` | `blacklist` | `blacklist` (bypass) or `whitelist` (only listed MACs) |
| `BYPASS_MACS_LIST` / `PROXY_MACS_LIST` | (empty) | MAC address list (space-separated) |
| `MARK_VALUE` | `20` | Traffic mark for IPv4 routing |
| `MARK_VALUE6` | `25` | Traffic mark for IPv6 routing |
| `TABLE_ID` | `2025` | Custom routing table ID |
| `LOG_TIMESTAMP` | `1` | Include timestamps in logs (0=off, 1=on) |
| `SKIP_CHECK_FEATURE` | `0` | Skip kernel checks (use with caution) |

#### Command Line Options

```
Usage: tproxy.sh {start|stop|restart|status} [options]

Commands:
  start     Apply proxy rules, routing tables, ipset, sysctl changes
  stop      Remove all added rules, routes, ipset sets, restore sysctl
  restart   stop → short delay → start
  status    Show current rules and routing (alias: check)

Options:
  -d DIR, --dir DIR       Specify config directory
  --dry-run               Simulate all operations (no real changes)
  --verbose               Show detailed debug logs
  -v, --version           Show version
  -h, --help              Show help
```

#### Stop

```bash
su -c "/data/adb/tproxy.sh stop"
su -c "/data/adb/tproxy.sh -d /data/adb stop"
```

#### Check Status

```bash
su -c "/data/adb/tproxy.sh status"

# Manual check
su -c iptables -t mangle -vL
su -c iptables -t nat -nvL
su -c ip rule show
su -c ip route show table all | grep 2025
```

---

### Proxy Client Examples

> The proxy core must listen on the specified port (default 1536) with TPROXY support. Usually requires running as root or with `cap_net_admin` capabilities.

#### Launching the Core on Android

**Using busybox setuidgid:**
```bash
su -c "busybox setuidgid $CORE_USER_GROUP /path/to/proxy-binary ..."
```

**For non-root users (custom UID:GID):**
```bash
# One time, as root:
su -c "setcap cap_net_admin,cap_net_bind_service,cap_net_raw+eip /path/to/proxy-binary"

# Launch:
su -c "busybox setuidgid $CORE_USER_GROUP /path/to/proxy-binary ..."
```

**Alternative via capsh:**
```bash
su -c "capsh --caps='cap_net_admin,cap_net_bind_service,cap_net_raw+eip' --addamb='cap_net_admin,cap_net_bind_service,cap_net_raw' --secbits=1 -- -c '/path/to/proxy-binary ...'"
```

#### sing-box Example

```json
{
  "dns": {
    "servers": [
      { "tag": "ali", "type": "https", "server": "223.6.6.6" }
    ],
    "independent_cache": true,
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tproxy",
      "tag": "tproxy_in",
      "listen": "::",
      "listen_port": 1536
    }
  ],
  "route": {
    "default_domain_resolver": "ali",
    "rules": [
      { "action": "sniff" },
      {
        "type": "logical", "mode": "or",
        "rules": [
          { "port": 53 },
          { "protocol": "dns" }
        ],
        "action": "hijack-dns"
      }
    ]
  }
}
```

#### Clash Example

```yaml
tproxy-port: 1536

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/15
  fake-ip-filter:
    - "*"
    - "+.lan"
    - "+.local"
  nameserver:
    - https://120.53.53.53/dns-query
    - https://223.5.5.5/dns-query
```

#### Clash Meta (mihomo) Example

```yaml
tproxy-port: 1536

proxies:
  - name: "DNS_Hijack"
    type: dns

rules:
  - DST-PORT,53,DNS_Hijack
```

#### xray / v2ray Example (dokodemo-door + tproxy)

```json
{
  "listen": "127.0.0.1",
  "port": 1536,
  "protocol": "dokodemo-door",
  "settings": {
    "network": "tcp,udp",
    "followRedirect": true
  },
  "streamSettings": {
    "sockopt": {
      "tproxy": "tproxy"
    }
  },
  "tag": "transparent-in"
}
```
