# VK TURN Client

VK TURN позволяет использовать VK-звонки как транспорт для проксирования трафика.

### Загрузка бинарного файла

Скачайте последнюю версию для Android ARMv8a:
[Releases · cacggghp/vk-turn-proxy](https://github.com/cacggghp/vk-turn-proxy/releases)

### Запуск

```bash
./vk-turn-proxy-client \
  -peer ваш_ip_vps:56000 \
  -vk-link "ссылка_на_звонок_vk" \
  -listen 127.0.0.1:9000 \
  -vless
```

### Параметры

| Параметр | Описание |
|----------|----------|
| `-peer` | Адрес и порт VK TURN на сервере (по умолчанию UDP 56000) |
| `-vk-link` | Ссылка на VK-звонок |
| `-listen` | Локальный адрес для прослушивания (Xray будет подключаться сюда) |
| `-vless` | Режим VLESS |

### Связка с Xray

В конфигурации Xray (`client_config.json`) в секции `outbounds` адрес указан как `127.0.0.1:9000` — это направит трафик Xray в локальный VK TURN прокси.

### Порядок запуска

1. Запустите `vk-turn-proxy-client`
2. Запустите Xray с конфигом, указывающим на `127.0.0.1:9000`
3. Запустите `tproxy.sh start`