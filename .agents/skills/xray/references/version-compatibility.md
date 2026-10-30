# Совместимость версий Xray-core

Использовать этот файл только для version-specific задач. При запросе о последних версиях заново проверить [официальные релизы](https://github.com/XTLS/Xray-core/releases) и исходный код: приведенные ниже статусы и defaults являются снимком на 2026-10-25, покрытым до `v26.10.21`. Теги `v26.10.10` и `v26.10.17` сняты upstream.

## Каналы релизов на 2026-10-25

- `v26.3.27` (2026-03-27) — был отмечен GitHub как `Latest` stable до 2026-10-21; сейчас GitHub `Latest` — `v26.10.21`.
- `v26.7.28` (2026-07-28) — pre-release после `v26.7.11`.
- `v26.9.8` (2026-09-08) — pre-release, **удалён upstream** (404); `v26.9.9` (2026-09-08) — pre-release.
- `v26.9.30` (2026-09-30) — pre-release; последний тег перед 26.10.x.
- `v26.10.10` (2026-10-10) — **снят upstream 2026-10-21**, ассеты 404; именно это ядро бандлит 3x-ui v3.10.2.
- `v26.10.17` (2026-10-17) — **снят upstream**, ассеты 404.
- `v26.10.21` (2026-10-21) — назначен `latest`; interim security release, полные notes обещаны позже.
- Тегов `v26.8.x` нет; промежуточных тегов между `v26.9.30` и `v26.10.21` не осталось (`v26.10.17` снят).
- 3x-ui: v3.10.2 пинится на `v26.10.10`; main уже переведён на `v26.10.21` ([commit `61b129d5`](https://github.com/MHSanaei/3x-ui/commit/61b129d5)), релиза с ним пока нет. Пересборка образа v3.10.2 из исходников сегодня невозможна (URL ядра 404) — использовать только опубликованный образ.

Не обновлять production до нового pre-release автоматически. Сначала определить текущую версию сервера и клиентов, прочитать полный диапазон изменений, зафиксировать точный tag/image digest и сохранить rollback artifact.

## Значимые изменения

### v26.6.22

- Удалены deprecated TLS fields `allowInsecure`, `echForceQuery` и `verifyPeerCertInNames`. Использовать нормальную CA/name verification; при явной необходимости pinning применять `pinnedPeerCertSha256` и `verifyPeerCertByName`. Источник: [PR #6226](https://github.com/XTLS/Xray-core/pull/6226).
- В XHTTP переименованы `sessionPlacement` в `sessionIDPlacement` и `sessionKey` в `sessionIDKey`; добавлены `sessionIDTable` и `sessionIDLength`. Не генерировать старые имена для новых core и проверять поддержку этих fields на клиентах. Источник: [PR #6258](https://github.com/XTLS/Xray-core/pull/6258).
- XHTTP, WebSocket, HTTPUpgrade и gRPC servers принимают `X-Forwarded-For` как доверенный только при подходящем `sockopt.trustedXForwardedFor`. Указывать узкие source IP/CIDR reverse proxy, не `0.0.0.0/0`. Источник: [PR #6309](https://github.com/XTLS/Xray-core/pull/6309).
- Исправлена работа `scStreamUpServerSecs` при `xPaddingObfsMode: true`, когда padding находится не в `Referer`. Для такого сочетания требовать как минимум `v26.6.22` на сервере. Источник: [PR #6343](https://github.com/XTLS/Xray-core/pull/6343).

### v26.6.27

- Клиентский default XHTTP XMUX изменен с одиночной concurrency-схемы на `maxConnections: 6`. Upstream profile:

```json
{
  "maxConcurrency": 0,
  "maxConnections": "6",
  "cMaxReuseTimes": 0,
  "hMaxRequestTimes": "600-900",
  "hMaxReusableSecs": "1800-3000",
  "hKeepAlivePeriod": 0
}
```

- По возможности использовать defaults самого target core. Копировать этот profile явно только для воспроизводимого развертывания, привязанного к версии, и повторно сверять его при следующем обновлении. Источник: [commit `18b85adb`](https://github.com/XTLS/Xray-core/commit/18b85adb4e288f49a7894351c6e0f2428c0beef6).

### v26.7.11

- REALITY server при отсутствующем явном значении устанавливал `minClientVer: "26.3.27"` (в v26.9.9 этот встроенный default снят — см. ниже). Источник: [commit `af7eb680`](https://github.com/XTLS/Xray-core/commit/af7eb680).
- Запрещены незашифрованные VLESS и Trojan outbounds к публичному Internet; для VMess и Shadowsocks удалены `none`/`zero`/`plain`. Исправлять legacy configs до обновления. Источник: [PR #6303](https://github.com/XTLS/Xray-core/pull/6303).
- `streamSettings.method` добавлен как новое имя transport method; `streamSettings.network` продолжает приниматься в `v26.7.11` для совместимости. Не переписывать `network` на `method`, пока не подтверждена версия всех consumers. Источник: [PR #6426](https://github.com/XTLS/Xray-core/pull/6426).
- XHTTP больше не добавляет trailing `/`, когда и `sessionID`, и `seq` размещены вне path. После обновления проверять фактический URL и route matching reverse proxy. Источник: [PR #6307](https://github.com/XTLS/Xray-core/pull/6307).
- Для `pinnedPeerCertSha256` требуется проверяемое имя из `serverName`, более приоритетного `verifyPeerCertByName` или outbound `address`. Источник: [PR #6472](https://github.com/XTLS/Xray-core/pull/6472).
- Добавлен root config `env`, а `xray run --env` удален. Не переносить старые startup commands без проверки. Источник: [PR #6400](https://github.com/XTLS/Xray-core/pull/6400).

### v26.7.28

- XHTTP: клиентский default XMUX `maxConnections` снижен с `"6"` до `"3"` («anti-TSPU»). Профиль из v26.6.27 больше не совпадает с upstream default; при явном задании значения сверять с целевой версией. Источник: [commit `18e283909c`](https://github.com/XTLS/Xray-core/commit/18e283909c).
- finalmask XMC (breaking, wire-incompatible): удален `mode`, список `usernames` заменен обязательным массивом `profiles` (username + UUID + Mojang-поля). Обновлять оба конца. Источник: [PR #6487](https://github.com/XTLS/Xray-core/pull/6487).
- REALITY: цели `.ru`/`.ir`/`.cn`/`apple`/`icloud`/`microsoft` получают `LogWarning` — конфиг не отклоняется, несмотря на формулировку PR. Источник: [PR #6508](https://github.com/XTLS/Xray-core/pull/6508).
- TUN inbound: default `name` → `"utunN"` (10–1024); Windows `desc` → `"Wintun"`. Источники: [PR #6485](https://github.com/XTLS/Xray-core/pull/6485), [PR #6486](https://github.com/XTLS/Xray-core/pull/6486).
- XHTTP и gRPC servers: точный `localAddr`. Источник: [PR #6526](https://github.com/XTLS/Xray-core/pull/6526).

### v26.9.8 / v26.9.9

Официальный changelog для этих тегов отсутствует (тела релизов пусты); список реконструирован по [compare v26.7.11...v26.9.9](https://github.com/XTLS/Xray-core/compare/v26.7.11...v26.9.9), PR/commit pages и заметкам панелей.

- REALITY handshake (де-факто минимум клиента): bump `xtls/reality` до `20260908062103` — ClientHello без post-quantum keyshare X25519MLKEM768 перед X25519 отбрасывается. Старые клиенты могут перестать проходить handshake. Источники: [commit `47cfe9994a`](https://github.com/XTLS/Xray-core/commit/47cfe9994a), [REALITY commit `8cdf7bf9c7`](https://github.com/XTLS/REALITY/commit/8cdf7bf9c7).
- REALITY `minClientVer`: встроенный default `26.3.27` снят; пустое значение теперь означает «без минимума». При необходимости задавать `minClientVer` явно. Источники: [файл v26.7.28](https://github.com/XTLS/Xray-core/blob/v26.7.28/infra/conf/transport_security.go#L117-L119), [файл v26.9.9](https://github.com/XTLS/Xray-core/blob/v26.9.9/infra/conf/transport_security.go#L118-L119), [3x-ui v3.8.0](https://github.com/MHSanaei/3x-ui/releases/tag/v3.8.0).
- finalmask `udpHop` (breaking config): `quicParams.udpHop` вынесен в отдельную UDP-маску `udphop` (`"type": "udphop"`); старый ключ молча игнорируется. Источник: [PR #6327](https://github.com/XTLS/Xray-core/pull/6327).
- VLESS: исправлен `validateOutboundTransportSecurity()` для запрета незашифрованных публичных VLESS/Trojan outbounds. Источник: [PR #6741](https://github.com/XTLS/Xray-core/pull/6741).
- freedom/`dialerProxy`: домен больше не резолвится и `finalRules` не применяются (freedom не является финальным outbound). Источник: [PR #6742](https://github.com/XTLS/Xray-core/pull/6742).
- Прочее по диапазону: `localOS` в routing ([PR #6553](https://github.com/XTLS/Xray-core/pull/6553)), WireGuard `remoteDNS` и TTL ([PR #6620](https://github.com/XTLS/Xray-core/pull/6620)), Blackhole response data ([PR #6713](https://github.com/XTLS/Xray-core/pull/6713)), QUICv2 в sniffing ([PR #6695](https://github.com/XTLS/Xray-core/pull/6695)), Hysteria 2.12.2 ([PR #6565](https://github.com/XTLS/Xray-core/pull/6565)), toolchain Go 1.27.x ([commit `fd2ca74822`](https://github.com/XTLS/Xray-core/commit/fd2ca74822)). Переименований XHTTP `extra`/`xmux`/session-placement в диапазоне нет; `streamSettings.method` и `network` сосуществуют.

### v26.9.30

- XDNS finalmask переведён в объектную форму ([PR #6718](https://github.com/XTLS/Xray-core/pull/6718)); в v26.10.10 поля переименованы в `names`/`addrs` (см. ниже).
- WireGuard outbound: удалены `settings.domainStrategy` и режим `remoteDNS: "local"`; переносить в `sockopt.domainStrategy` / `targetStrategy`. Старый режим паникует ядро на старте, старый ключ молча игнорируется ([PR #6771](https://github.com/XTLS/Xray-core/pull/6771)).
- TUN: `autoSystemDNS` → `autoSystemDnsToGateway`; добавлен `autoSystemWfpBlockLeak` (Windows) ([PR #6853](https://github.com/XTLS/Xray-core/pull/6853)).
- Transport refactor на dialer/listener из Finalmask ([PR #6754](https://github.com/XTLS/Xray-core/pull/6754)): конфиг без масок эквивалентен прежнему; UDS-listen с `port: 0` сохранён.
- XTLS Vision: suppress outer `CloseNotify` после перехода в direct copy ([PR #6834](https://github.com/XTLS/Xray-core/pull/6834)). Актуально при собственном TLS/REALITY; за внешним TLS или plaintext UDS — no-op.

### v26.10.10 (снят upstream)

- TLS client перешёл на встроенные Mozilla RootCAs вместо OS store; добавлен `tlsSettings.useSystemCA` (default `false`) ([PR #7105](https://github.com/XTLS/Xray-core/pull/7105)). Outbound к серверу с приватно установленным CA требует явного `useSystemCA: true`.
- XDNS finalmask: поля переименованы в `names: []string` и `addrs: []string` ([PR #7090](https://github.com/XTLS/Xray-core/pull/7090)); старые ключи молча игнорируются, клиенту нужен core ≥ 26.10.10.
- Lua-скрипты DNS и routing: `dns.script`, `dns.servers[].id`, `routing.script` ([PR #6823](https://github.com/XTLS/Xray-core/pull/6823)) — аддитивно.
- MASQUE WARP: `masqueSettings.warp{...}` ([PR #6878](https://github.com/XTLS/Xray-core/pull/6878)) — опционально.
- XHTTP, VLESS, REALITY, XTLS-Vision и `vlessenc` в диапазоне 26.9.30→26.10.10 не менялись.
- **Снят 2026-10-21**: не пиновать для пересборок и не считать стабильным источником бинарника.

### v26.10.17 (снят upstream)

- Серия фиксов XDRIVE/Lua/TUN и совместимость XTLS Vision с Go 1.27.3+; тег и ассеты удалены upstream.

### v26.10.21

- Interim security release, помечен `latest`: из встроенного RootCAs удалены 3 корневых сертификата ([#7212](https://github.com/XTLS/Xray-core/pull/7212), компрометация приватных ключей intermediate CA), сборка Go 1.27.3.
- XTLS Vision: исправлен SIGSEGV на Go 1.27.3+ ([PR #7176](https://github.com/XTLS/Xray-core/pull/7176)). Не пересобирать `v26.10.10`/`v26.10.17` тулчейном ≥ 1.27.3.
- Полные release notes обещаны позже; трактовать как interim.

## Проверка обновления

1. Получить `xray version` на сервере и версии core в реальных клиентах.
2. Сравнить installed tag с target tag по официальному GitHub compare/release history; не пинить снятые теги.
3. Проверить REALITY: `minClientVer` (снятый default), поддержку X25519MLKEM768 у клиентов, `serverNames`/shortIds; TLS fields и public chained outbounds.
4. Проверить XHTTP: `sessionID*`, XMUX/padding defaults (6→3), `trustedXForwardedFor`, отсутствие переименований `extra`.
5. Проверить finalmask-конфиги: XMC `profiles`, `quicParams.udpHop` → маска `udphop`, XDNS `names`/`addrs`.
6. TLS outbound: учесть bundled RootCAs (с 26.10.10) и `useSystemCA` для приватных CA.
7. Запустить `xray run -test -config <config-path>` на target binary до restart.
8. Проверить один реальный клиент из внешней сети, затем выполнить постепенный rollout.
9. Сохранить старый binary/image и config backup до подтверждения всех критичных клиентских путей.
