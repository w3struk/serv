# Совместимость версий Xray-core

Использовать этот файл только для version-specific задач. При запросе о последних версиях заново проверить [официальные релизы](https://github.com/XTLS/Xray-core/releases) и исходный код: приведенные ниже статусы и defaults являются снимком на 2026-07-13.

## Каналы релизов на 2026-07-13

- `v26.3.27` — релиз, отмеченный GitHub как `Latest` stable.
- `v26.7.11` — самый новый опубликованный `Pre-release`.
- `v26.6.22`, `v26.6.27` и `v26.7.11` — pre-release цепочка после `v26.6.1`.

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

- REALITY server при отсутствующем явном значении устанавливает `minClientVer: "26.3.27"`. До обновления проверить все client cores; не понижать default без прямого решения о совместимости и риске. Источник: [commit `af7eb680`](https://github.com/XTLS/Xray-core/commit/af7eb680).
- Запрещены незашифрованные VLESS и Trojan outbounds к публичному Internet; для VMess и Shadowsocks удалены `none`/`zero`/`plain`. Исправлять legacy configs до обновления. Источник: [PR #6303](https://github.com/XTLS/Xray-core/pull/6303).
- `streamSettings.method` добавлен как новое имя transport method; `streamSettings.network` продолжает приниматься в `v26.7.11` для совместимости. Не переписывать `network` на `method`, пока не подтверждена версия всех consumers. Источник: [PR #6426](https://github.com/XTLS/Xray-core/pull/6426).
- XHTTP больше не добавляет trailing `/`, когда и `sessionID`, и `seq` размещены вне path. После обновления проверять фактический URL и route matching reverse proxy. Источник: [PR #6307](https://github.com/XTLS/Xray-core/pull/6307).
- Для `pinnedPeerCertSha256` требуется проверяемое имя из `serverName`, более приоритетного `verifyPeerCertByName` или outbound `address`. Источник: [PR #6472](https://github.com/XTLS/Xray-core/pull/6472).
- Добавлен root config `env`, а `xray run --env` удален. Не переносить старые startup commands без проверки. Источник: [PR #6400](https://github.com/XTLS/Xray-core/pull/6400).

## Проверка обновления

1. Получить `xray version` на сервере и версии core в реальных клиентах.
2. Сравнить installed tag с target tag по официальному GitHub compare/release history.
3. Проверить REALITY `minClientVer`, TLS fields, public chained outbounds, XHTTP `sessionID*`, XMUX/padding и `trustedXForwardedFor`.
4. Запустить `xray run -test -config <config-path>` на target binary до restart.
5. Проверить один реальный клиент из внешней сети, затем выполнить постепенный rollout.
6. Сохранить старый binary/image и config backup до подтверждения всех критичных клиентских путей.
