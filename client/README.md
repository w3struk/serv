# Настройка клиента

### Требования

- Android-устройство с root-правами (Magisk / KernelSU / APatch)
- Команды `iptables`/`ip6tables` + `ip`
- Команда `curl` (для загрузки списков RU IP)
- Модули ядра: `xt_TPROXY`, `xt_owner`, `xt_mac`, `ip_set` + `xt_set`
- Прокси-клиент, слушающий на localhost с поддержкой TPROXY (Xray, sing-box, Clash Meta)

### Прозрачный прокси (tproxy.sh)

#### Установка

```bash
curl https://raw.githubusercontent.com/w3struk/steal-oneself/main/client/tproxy/tproxy.sh -o /data/adb/tproxy.sh
chmod 755 /data/adb/tproxy.sh
```

#### Настройка

Создайте `/data/adb/tproxy.conf` (см. [tproxy/tproxy.conf.example](tproxy/tproxy.conf.example)):

```bash
PROXY_TCP_PORT=12345
PROXY_UDP_PORT=12345
PROXY_MODE=1
DNS_HIJACK_ENABLE=1
DNS_PORT=1053
BLOCK_QUIC=1
BYPASS_RU_IP=1
CORE_USER_GROUP="root:net_admin"
```

> **Важно:** `PROXY_TCP_PORT`/`PROXY_UDP_PORT` должны совпадать с портом inbound в вашем конфиге Xray/sing-box.

#### Запуск

```bash
# Установка правил
su -c "/data/adb/tproxy.sh start"

# Проверка статуса
su -c "/data/adb/tproxy.sh status"

# Остановка
su -c "/data/adb/tproxy.sh stop"
```

#### Свой каталог конфигов (рекомендуется)

```bash
su -c "/data/adb/tproxy.sh -d /data/adb/ start"
```

### Xray

Используйте конфиг [configs/xray.json](configs/xray.json).

Замените `YOUR_UUID_FROM_3XUI` на UUID из панели 3x-ui.

```bash
./xray-linux-arm64 -c xray.json
```

### sing-box

Используйте конфиг [configs/singbox.json](configs/singbox.json).

Замените `YOUR_UUID_FROM_3XUI` на UUID из панели 3x-ui.

```bash
./sing-box run -c singbox.json
```

### Clash Meta (mihomo)

Используйте конфиг [configs/clash_meta.yaml](configs/clash_meta.yaml).

Замените `YOUR_UUID_FROM_3XUI` на UUID из панели 3x-ui.

### VK TURN

См. [vk-turn/README.md](vk-turn/README.md)
