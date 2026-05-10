# 3x-ui + Caddy + VLESS + XHTTP + TLS — полная схема проксирования

## Архитектура

**Сервер (`server/`):**
- **Caddy** — reverse proxy, выпуск/обновление TLS-сертификатов
- **3x-ui** — панель управления Xray (VLESS inbounds)
- **Lampac** — маскировочный сайт

**Клиент (`client/`):**
- **tproxy.sh** — прозрачный прокси (TPROXY) для Android
- **Xray / sing-box** — прокси-клиент

## Быстрый старт

1. **[Настройка сервера →](server/README.md)** — VPS, Docker, 3x-ui, Caddy
2. **[Настройка клиента →](client/README.md)** — Android, tproxy.sh, Xray

## Благодарности

- [Akiyamov](https://github.com/Akiyamov/xray-vps-setup) — xray-vps-setup
- [ampetelin](https://github.com/ampetelin/3x-ui-aio) — 3x-ui-aio
- [MHSanaei](https://github.com/MHSanaei/3x-ui) — 3x-ui
- [Lampac NextGen](https://github.com/lampac-nextgen/lampac)
- [CHIZI-0618](https://github.com/CHIZI-0618/) — AndroidTProxyShell

## полезное
docker compose down && docker compose up -d && docker compose logs -f
docker system prune -a --volumes - Очистить все данные (контейнеры, образы, тома)