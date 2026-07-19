---
name: xray
description: Развертывать, обновлять и администрировать безопасные серверные конфигурации Xray-core для VLESS, VMess, Trojan и Shadowsocks с Reality, XTLS-Vision, XHTTP, WebSocket, gRPC, HTTP/2, TLS, CDN-туннелированием, маршрутизацией, fallbacks, защищенными панелями управления, подписками, несколькими пользователями и клиентскими ссылками. Использовать при установке или обновлении Xray-core, проверке совместимости версий, настройке сервера и клиента, диагностике соединений и подготовке share links.
---

# Развертывание серверов Xray

Применять этот навык для установки, настройки, обновления, диагностики и генерации серверных или клиентских конфигураций Xray-core. Сосредоточиться на безопасных и сопровождаемых серверных решениях для систем, которыми пользователь владеет или которые имеет право администрировать.

## Основные принципы

- Выбирать самую простую безопасную схему, удовлетворяющую сетевым ограничениям пользователя.
- Перед изменением работающего сервера проверять ОС, пакетный менеджер, домен и DNS, firewall, точную версию Xray-core, путь к конфигурации и service manager.
- Перед редактированием создавать резервную копию конфигурации, обычно `/usr/local/etc/xray/config.json`.
- Не публиковать private keys, UUID, passwords, short IDs, API tokens и учетные данные панели.
- До перезапуска проверять конфигурацию: `xray run -test -config /usr/local/etc/xray/config.json`.
- Минимизировать поверхность атаки: привязывать транспорты за локальным reverse proxy к `127.0.0.1`, ограничивать management API localhost и блокировать private/reserved destinations, если доступ к LAN явно не требуется.
- Не открывать Xray management API на публичном интерфейсе.
- Не генерировать `allowInsecure`: в современных версиях Xray-core поле удалено. Исправлять certificate chain, SNI и проверку имени; применять `pinnedPeerCertSha256` только при осознанном pinning и вместе с корректным `serverName`, `verifyPeerCertByName` или адресом outbound.
- Не предлагать plaintext HTTP для панелей управления. Размещать 3x-ui/x-ui и другие панели за HTTPS, localhost, SSH tunnel, VPN или доверенным reverse proxy.
- Проверять соответствие развертывания требованиям закона, провайдера и организации пользователя.

## Проверка версии и совместимости

Перед генерацией конфигурации или обновлением:

- Получить точную версию серверного бинарника через `xray version` и версии core во всех используемых клиентах. Для 3x-ui/x-ui проверять встроенный Xray binary отдельно от версии панели.
- Сверить установленный и целевой теги с официальными [Xray-core Releases](https://github.com/XTLS/Xray-core/releases). Отличать `Latest` stable от `Pre-release`; не считать самый новый тег автоматически подходящим для production.
- В production фиксировать точный тег или image digest и сохранять проверенный rollback artifact. Не переключать развертывание на изменяемые `latest` или `pre-release` без прямого решения пользователя.
- Читать [матрицу совместимости версий](references/version-compatibility.md), если задача касается обновления, REALITY, XHTTP `extra`/XMUX/padding/session placement, TLS pinning, legacy ciphers или старых клиентов.
- Считать матрицу датированным снимком. При запросе о последних изменениях повторно проверять upstream release, относящиеся PR/commits и диапазон изменений от установленного тега до целевого.
- Сравнивать совместимость сервера со всеми реальными клиентами и панелями, затем сначала проверять обновление на одном клиенте или тестовом inbound.

## Источники upstream

Использовать релизы и исходный код как источник фактического поведения, а discussions — как сигналы дизайна и эксплуатации:

- Xray-core Releases: <https://github.com/XTLS/Xray-core/releases>
- Xray-core Discussions: <https://github.com/XTLS/Xray-core/discussions>
- Архитектура и назначение XHTTP: <https://github.com/XTLS/Xray-core/discussions/4113>
- XHTTP five-in-one с сочетаниями Reality direct/CDN: <https://github.com/XTLS/Xray-core/discussions/4118>
- Предложение стандарта XTLS subscriptions: <https://github.com/XTLS/Xray-core/discussions/4877>
- Блокировка private LAN targets и обход через `freedom.finalRules`: <https://github.com/XTLS/Xray-core/discussions/6157>
- Удаление `allowInsecure` и безопасный доступ к панелям: <https://github.com/XTLS/Xray-core/discussions/6250>

## Данные, которые нужно собрать

До подготовки итоговой конфигурации запросить или определить:

- ОС сервера, CPU architecture и наличие systemd.
- Точную версию Xray-core на сервере, версии core в клиентах и целевой release channel.
- Наличие Xray-core, 3x-ui, x-ui, Caddy, Nginx или другого reverse proxy.
- Public IP, domain name, состояние DNS и использование Cloudflare/CDN proxying.
- Требуемый inbound protocol: VLESS, VMess, Trojan или Shadowsocks.
- Требуемый transport/security: Reality, XTLS-Vision, TLS, XHTTP, WebSocket, gRPC или HTTP/2.
- Необходимость прохождения трафика через CDN/reverse proxy.
- Передает ли reverse proxy `X-Forwarded-For`, и какие точные IP/CIDR должны считаться доверенными.
- Доступные порты, особенно `443/tcp` и `80/tcp`, и наличие других web services на них.
- Нужен ли доступ к private/LAN addresses, например `10.0.0.0/8`, `172.16.0.0/12` или `192.168.0.0/16`.
- Наличие chained VLESS/Trojan/VMess/Shadowsocks outbounds и способ их шифрования.
- Число пользователей и необходимость labels, accounting или quotas для каждого пользователя.
- Требования клиентского приложения и необходимость share links, QR payloads или полного client JSON.

Если изменение firewall способно прервать SSH-доступ, предупредить пользователя и сохранить текущий SSH port до применения изменений.

## Типовые варианты развертывания

### Reality + VLESS + XTLS-Vision

Выбирать этот вариант для прямых подключений к серверу без CDN, когда требуется современный TLS-подобный handshake и устойчивость к пассивному fingerprinting.

Основные правила:

- Использовать `vless` inbound.
- Использовать `security: reality`.
- Использовать `network: raw` или `network: tcp` с учетом версии Xray и существующего стиля конфигурации; в новых примерах часто применяется `raw`. Для поддерживающих Vision клиентов сохранять `flow: xtls-rprx-vision`.
- Генерировать отдельный UUID для каждого пользователя.
- Генерировать X25519 keys для Reality.
- Выбирать реалистичный `serverNames`/SNI target и проверять его доступность. При использовании собственного домена осознанно настраивать fallback/website и сохранять строгую проверку сертификата.
- Использовать short IDs с достаточной энтропией и не публиковать их.
- Использовать поддерживаемые клиентом `fingerprint`/uTLS settings; не компенсировать несовместимость отключением проверки.
- Перед обновлением сервера проверять default `minClientVer` целевой версии и версии всех клиентов. Не понижать `minClientVer` молча ради совместимости.

Полезные команды:

```sh
xray uuid
xray x25519
openssl rand -hex 8
```

### TLS + WebSocket/gRPC/HTTP2 за CDN

Использовать этот вариант главным образом для совместимости со старыми клиентами или существующей инфраструктурой. Для новых HTTP-based deployments сначала оценивать XHTTP.

Основные правила:

- Завершать TLS на Caddy/Nginx/CDN, когда это соответствует архитектуре.
- Привязывать локальный listener Xray к `127.0.0.1`, если reverse proxy работает на том же сервере.
- Использовать трудно угадываемые paths для WebSocket или XHTTP.
- Для gRPC задавать неочевидный `serviceName` и проверять поддержку HTTP/2 upstream в reverse proxy.
- Если reverse proxy передает `X-Forwarded-For`, задавать `sockopt.trustedXForwardedFor` только для его точных source IP/CIDR; не доверять `0.0.0.0/0`.
- Не пытаться передавать raw TCP Reality через CDN без подтвержденной поддержки конкретного провайдера.
- Размещать безопасный website или fallback на публичном hostname.

### TLS + XHTTP за CDN или reverse proxy

Выбирать этот вариант для современных HTTP-based deployments, особенно при использовании CDN, reverse proxies, HTTP middleboxes или раздельных upload/download paths. Считать XHTTP основным HTTP transport Xray, а WebSocket/gRPC использовать преимущественно для требований совместимости.

Основные правила:

- Использовать Xray inbound `network: xhttp`. Для конфигураций, привязанных к новым версиям, учитывать alias `streamSettings.method`; сохранять `network` при необходимости совместимости со старыми core.
- Использовать трудно угадываемый `path`.
- Привязывать listener Xray к `127.0.0.1`, если он находится за локальным reverse proxy.
- Завершать TLS на Caddy/Nginx/CDN, когда это соответствует архитектуре.
- Проверять поддержку выбранных XHTTP features на сервере и клиенте; five-in-one examples требуют как минимум Xray-core v24.12.15 на обеих сторонах.
- Для совместимости предпочитать server `xhttpSettings.mode: "auto"`, а client upload mode настраивать только при необходимости.
- Использовать актуальные имена `sessionIDPlacement`, `sessionIDKey`, `sessionIDTable` и `sessionIDLength`; не переносить старые `sessionPlacement`/`sessionKey` без проверки целевой версии.
- Если reverse proxy передает `X-Forwarded-For`, ограничивать `sockopt.trustedXForwardedFor` точными адресами proxy.
- По умолчанию полагаться на XHTTP/XMUX defaults целевой версии. Фиксировать XMUX явно только для воспроизводимого version-pinned rollout и сверять значения с upstream.
- Включать XHTTP `extra`, XMUX и advanced padding только при конкретной необходимости. Сначала отдельно проверять безопасную конфигурацию по умолчанию, затем opt-in параметры.
- Не копировать public example paths дословно. Генерировать уникальный path и URL-encode его в share links.
- Сочетать Reality direct и XHTTP CDN на одном `443/tcp` только при осознанной настройке fallbacks, SNI split и проверенном поведении reverse proxy.
- Не считать raw TCP Reality совместимым с CDN; для CDN legs использовать XHTTP/TLS, если не подтвержден иной путь конкретного провайдера.

Пример inbound fragment:

```json
{
  "listen": "127.0.0.1",
  "port": 10001,
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "<uuid>",
        "email": "user@example"
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": {
      "path": "/<hard-to-guess-path>",
      "mode": "auto"
    }
  }
}
```

### Trojan

Использовать Trojan, когда нужна password-based совместимость с TLS-aware clients. Применять сильные случайные passwords, TLS и нормальный web fallback. Не создавать незашифрованный Trojan outbound к публичному адресу.

### Shadowsocks

Использовать Shadowsocks, когда нужна простая symmetric-key совместимость. Выбирать поддерживаемые клиентами AEAD ciphers, например `2022-blake3-aes-128-gcm` или `chacha20-ietf-poly1305`. Не использовать удаленные `none`, `zero` или `plain`.

## Проверка конфигурации

При генерации `/usr/local/etc/xray/config.json` включать необходимые разделы:

- `log`: задавать подходящий `loglevel`; не оставлять чрезмерно подробные production logs вне диагностики.
- `inbounds`: определять protocol, clients, stream settings, fallbacks и sniffing.
- `outbounds`: добавлять как минимум `direct`, `block` и запрошенные proxy/chained outbounds.
- `routing`: блокировать private/reserved IP ranges для публичного сервиса, при необходимости маршрутизировать ads/malware domains и сохранять direct outbound для обычного трафика.
- `policy`: настраивать user levels, handshake limits, idle timeouts и uplink/downlink stats, если они нужны.
- `stats` и `api`: включать только при необходимости monitoring и привязывать API access к localhost.

Для новых Xray-core не создавать незашифрованные VLESS/Trojan outbounds к публичному Internet и не использовать `none`/`zero`/`plain` для VMess или Shadowsocks. Если конфигурация унаследована, исправить transport security до обновления core.

Базовые меры маршрутизации для публичных proxy services:

- Блокировать `geoip:private`, если доступ к private networks не требуется.
- Блокировать или отдельно обрабатывать metadata endpoints облачных провайдеров.
- Не допускать DNS leaks через непредусмотренные resolvers.
- Учитывать, что в новых Xray-core `freedom` может по умолчанию блокировать private/reserved destinations для inbound protocols, включая VLESS, VMess, Trojan, Hysteria и WireGuard. Для намеренного доступа к LAN добавлять узкие allow rules в `freedom.settings.finalRules` и направлять на специальный outbound только нужные inbound tags, IPs, ports и networks. Не разрешать все private ranges целиком.

Пример узкого разрешения LAN:

```json
{
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "finalRules": [
          {
            "action": "allow",
            "network": "tcp",
            "ip": ["192.168.1.1"],
            "port": "9100"
          }
        ]
      },
      "tag": "lan-node-exporter"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["reality-in"],
        "ip": ["192.168.1.1"],
        "port": "9100",
        "outboundTag": "lan-node-exporter"
      }
    ]
  }
}
```

## Несколько пользователей

Для каждого пользователя:

- Генерировать отдельный UUID/password/key.
- Добавлять понятный `email`/label, например `alice@example` или `user-001`.
- Хранить учетные данные пользователей раздельно в notes или password manager; не выводить secrets без необходимости.
- При включенных stats настраивать user levels и объяснять способ проверки usage.

Пример команды UUID:

```sh
xray uuid
```

## Ссылки подключения (share links)

Включать в client links только обязательные для клиента и protocol поля. Предупреждать, что реализации клиентов могут использовать разные parameter names.

Распространенные форматы:

- VLESS: `vless://<uuid>@<host>:<port>?type=<network>&security=<security>&flow=<flow>&sni=<sni>&fp=<fingerprint>&pbk=<public-key>&sid=<short-id>#<name>`
- VMess: base64-encoded JSON внутри `vmess://...`
- Trojan: `trojan://<password>@<host>:<port>?type=<network>&security=tls&sni=<sni>#<name>`
- Shadowsocks: `ss://...`

Всегда URL-encode names, paths, service names и другие query values в итоговых links.

Для subscriptions предпочитать JSON-based XTLS formats, когда нужны structured distribution, несколько nodes, DNS/routing payloads, headers, HWID/device metadata или provider compatibility. Оставлять plaintext link lists только для простого ad hoc sharing.

## Проверка и эксплуатация

До перезапуска:

```sh
xray run -test -config /usr/local/etc/xray/config.json
```

Для systemd installs:

```sh
systemctl status xray --no-pager
systemctl restart xray
journalctl -u xray --no-pager -n 100
```

Для Docker-based deployments сначала проверять `docker-compose.yml`, mounted config paths, container names, точный image tag и встроенную версию Xray-core.

После перезапуска:

- Проверить listeners на ожидаемых ports.
- Проверить firewall rules.
- Выполнить тест из внешней client network, а не только с localhost.
- Проверить logs на handshake, TLS, routing, fallback и compatibility errors.
- Сохранить подтвержденный rollback path до завершения клиентской проверки.

## Диагностика

- Connection timeout: проверить DNS, firewall, provider security groups, listening ports и reverse proxy upstreams.
- TLS handshake failure: проверить SNI, certificate, ALPN, reverse proxy mode и client fingerprint settings.
- Certificate/import warnings: исправить certificate chain, SNI, client fingerprint или HTTPS panel setup; не включать insecure verification.
- Reality failure: проверить public/private key pair, `serverNames`, `shortIds`, client `pbk`, `sid`, `sni`, time synchronization и `minClientVer` относительно версии клиента.
- Config test отклоняет outbound после обновления: проверить незашифрованные public VLESS/Trojan outbounds и удаленные VMess/Shadowsocks ciphers.
- Private LAN target блокируется с `proxy/freedom: blocked target`: добавить узкий `finalRules` allow outbound и отдельное routing rule только для нужной цели.
- `X-Forwarded-For` игнорируется как forged: проверить `sockopt.trustedXForwardedFor` и фактический source address reverse proxy.
- WebSocket failure: проверить path, HTTP upgrade headers, CDN WebSocket support и upstream bind address.
- XHTTP failure: проверить версии Xray на обеих сторонах, актуальные `sessionID*` fields, `path`, `mode`, reverse proxy buffering, HTTP/2/H3 support, CDN limits, upload/download SNI split и поддержку выбранных features клиентом.
- XHTTP route перестал совпадать после обновления: проверить trailing slash и placement для `sessionID`/`seq`, затем сопоставить фактический request path с правилами reverse proxy.
- gRPC failure: проверить HTTP/2 support, service name, reverse proxy gRPC directives и CDN compatibility.
- Низкая скорость: проверить congestion control, MTU, CPU AES support, CDN path, routing и provider throttling.
- Клиент импортирует профиль, но не подключается: сравнить share link с полным JSON, проверить URL encoding и реальную версию client core.

## Особенности репозитория

Для XHTTP в этом репозитории:

- Изменять генерируемый payload через `build_xhttp_payload()` и синхронно обновлять относящуюся документацию.
- Сравнивать значения и семантику defaults с целевым upstream commit/release, а не только наличие JSON fields.
- Сохранять production defaults безопасными, а advanced XHTTP padding/obfuscation — явным opt-in.
- Проверять default и opt-in payloads отдельно через `jq -e`, разбирать вложенный `streamSettings` и выполнять `bash -n setup.sh`, `docker compose config --quiet` и `git diff --check` до публикации.
