# steal-oneself

> 3x-ui + Caddy + VLESS + XHTTP + TLS + VK TURN — полная схема проксирования

---

## Схема

**Клиент → VK TURN → Сервер (3x-ui) → Интернет**

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────┐
│  Android    │────▶│  VK TURN     │────▶│  3x-ui      │────▶│ Internet │
│  клиент     │     │  transport   │     │  (Xray)     │     │          │
│             │     │  (UDP 56000) │     │  :2024      │     │          │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────┘
  │ tproxy.sh                               │ Caddy
  │ Xray/sing-box/Clash                     │ Lampac (маскировка)
  │                                         │ TLS через Caddy (:443)
```

### Архитектура

**Сервер (`server/`):**
- **Caddy** — reverse proxy, выпуск/обновление TLS-сертификатов
- **3x-ui** — панель управления Xray (VLESS inbounds)
- **Lampac NextGen** — маскировочный сайт
- **VK TURN Proxy** — приём трафика из VK-звонков

**Клиент (`client/`):**
- **tproxy.sh** — прозрачный прокси (TPROXY) для Android
- **Xray / sing-box / Clash Meta** — прокси-клиент
- **VK TURN Client** — клиентская часть VK TURN транспорта

### Быстрый старт

1. **[Настройка сервера →](server/README.md)** — VPS, Docker, 3x-ui, Caddy
2. **[Настройка клиента →](client/README.md)** — Android, tproxy.sh, Xray

---

## Структура проекта

```
steal-oneself/
├── README.md              # Этот файл
├── server/                # Серверная часть
│   ├── README.md          # Инструкция по развёртыванию
│   ├── docker-compose.yml
│   ├── Caddyfile
│   ├── lampac/
│   ├── assets/
│   └── scripts/
│       ├── firewall.sh
│       └── setup.sh
├── client/                # Клиентская часть
│   ├── README.md          # Инструкция по настройке
│   ├── tproxy/
│   │   ├── tproxy.sh
│   │   └── tproxy.conf.example
│   ├── configs/
│   │   ├── xray.json
│   │   ├── singbox.json
│   │   └── clash_meta.yaml
│   └── vk-turn/
│       └── README.md
└── docs/                  # Общая документация
    ├── ssh-setup.md
    ├── docker-install.md
    └── bbr-setup.md
```

---

## Благодарности

- [Akiyamov](https://github.com/Akiyamov/xray-vps-setup) — xray-vps-setup
- [ampetelin](https://github.com/ampetelin/3x-ui-aio) — 3x-ui-aio
- [MHSanaei](https://github.com/MHSanaei/3x-ui) — 3x-ui
- [Lampac NextGen](https://github.com/lampac-nextgen/lampac)
- [CHIZI-0618](https://github.com/CHIZI-0618/) — AndroidTProxyShell
- [cacggghp](https://github.com/cacggghp/vk-turn-proxy) — vk-turn-proxy
