# Xray JSON → sing-box-extended

Статический конвертер работает только в браузере. Он извлекает из наблюдаемой клиентской JSON-подписки 3x-ui/Xray узкий, проверяемый набор VLESS-outbound и создаёт `outbounds` для **shtorm-7/sing-box-extended `v1.13.14-extended-2.5.1`** (закреплённый коммит `df395464850beb1e1ea992943b124f8432520a71`). Ветка `extended` без этого коммита не является целью конвертации.

Проверенный producer: `ghcr.io/mhsanaei/3x-ui:latest` с digest `sha256:344f7a68a91e59d592fc355d67e32d8c2041b1c2082a7eaa3c413dc3a5cab7db`, содержащий Xray `26.7.11`. Более новый образ с тегом `latest` не становится проверенным автоматически.

## Вход и результат

Вход — один JSON/JSONC-объект до 1 МиБ с массивом верхнего уровня `outbounds` не длиннее 32 элементов. Поддерживаются только безопасные комментарии `//` и `/*…*/` вне строк и trailing comma; URLs и другие строки не изменяются. Это не универсальный импортёр Xray-конфигураций: принимается только описанный ниже клиентский поднабор. Результат всегда имеет оболочку:

```json
{ "outbounds": [] }
```

Это JSONC-совместимый **набор outbound**, а не готовый профиль. Конвертер не добавляет DNS, `inbounds`, маршрутизацию, `direct`/`block` или системные значения.

Минимальный синтетический TLS-пример без секретов:

```json
{
  "outbounds": [{
    "protocol": "vless",
    "tag": "synthetic-vless",
    "settings": {
      "address": "example.invalid",
      "port": 443,
      "id": "00000000-0000-4000-8000-000000000001",
      "flow": "xtls-rprx-vision"
    },
    "streamSettings": {
      "network": "xhttp",
      "security": "tls",
      "tlsSettings": { "serverName": "example.invalid" },
      "xhttpSettings": {
        "path": "/xhttp",
        "mode": "stream-up",
        "xPaddingBytes": 1
      }
    }
  }]
}
```

## Матрица поддерживаемых параметров

Пути начинаются от элемента `outbounds[i]`. «Ошибка» означает фатальную диагностику и отсутствие всего результата; частичный bundle не выдаётся. Неуказанные поля не дополняются, кроме описанных значений по умолчанию. Неизвестные поля в принимаемых объектах отклоняются.

| Xray path | sing-box-extended path | Статус / проверка |
|---|---|---|
| `.protocol` | `.type` | Только `vless` → `vless`; остальные outbound пропускаются. |
| `.tag` | `.tag` | Сохраняется; пустой, повторный или некорректный заменяется детерминированным `vless-N`. |
| `.settings.address` | `.server` | Обязательная непустая строка без CR/LF. |
| `.settings.port` | `.server_port` | Обязательный целый порт `1…65535`. |
| `.settings.id` | `.uuid` | Обязательный UUID RFC 4122. |
| `.settings.flow` | `.flow` | Необязателен; допускается только точный `xtls-rprx-vision`. |
| `.settings.encryption` | `.encryption` | Пустое или `none` не выводится. Иное значение — только проверяемый формат `mlkem768x25519plus.(native\|xorpub\|random).(0rtt\|1rtt).<tail…>` с хотя бы одним base64url-ключом без `=` размером 32 либо 1184 байта. |
| `.streamSettings.network` | `.transport.type` | Обязательно `xhttp` → `xhttp`. |
| `.streamSettings.security: "tls"` | `.tls.enabled: true` | Поддерживается TLS-контракт ниже. |
| `.streamSettings.security: "reality"` | `.tls.enabled: true`, `.tls.reality` | Поддерживается только одобренный клиентский Reality-контракт ниже. |
| `.streamSettings.tlsSettings.serverName` | `.tls.server_name` | Необязательная строка. |
| `.streamSettings.tlsSettings.alpn` | `.tls.alpn` | Необязательный массив строк. |
| `.streamSettings.tlsSettings.allowInsecure` | — | Допустимо только `false` (не выводится); `true` — ошибка. |
| `.streamSettings.tlsSettings.fingerprint` | `.tls.utls.fingerprint` | Канонические: `chrome`, `firefox`, `edge`, `safari`, `360`, `qq`, `ios`, `android`; регистр нормализуется. |
| `.streamSettings.tlsSettings.settings.fingerprint` | `.tls.utls.fingerprint` | Совместимая вложенная форма. Допускается только ключ `fingerprint`; при наличии обеих форм значения должны совпасть после нормализации. |
| отсутствие fingerprint | `.tls.utls` | Включается uTLS с `fingerprint: "chrome"`. Поддерживаемые Xray auto-алиасы нормализуются: `hello{chrome,firefox,edge,safari,360,qq,ios}_auto`, `helloandroid_11_okhttp`. |
| `.streamSettings.xhttpSettings.path` | `.transport.path` | Обязательная строка, начинающаяся с `/`. |
| `.streamSettings.xhttpSettings.mode` | `.transport.mode` | Обязателен: `auto`, `packet-up`, `stream-up` или `stream-one`. |
| `.streamSettings.xhttpSettings.host` | `.transport.host` | Необязательная строка. `Host` нельзя передавать через `headers`. |
| `.streamSettings.xhttpSettings.headers` | `.transport.headers` | Необязательная карта строк; имена и значения без CR/LF, ключ `Host` запрещён. |
| `.streamSettings.xhttpSettings.{xPaddingBytes, scMaxEachPostBytes, scMinPostsIntervalMs, sessionIDLength, uplinkChunkSize}` | `.transport.{x_padding_bytes, sc_max_each_post_bytes, sc_min_posts_interval_ms, session_id_length, uplink_chunk_size}` | Число или диапазон `min-max`, нормализуется. `xPaddingBytes` обязателен и сохраняется из источника; отсутствие, пустое/нулевое/некорректное значение отвергается. Положительны также `scMaxEachPostBytes`, `sessionIDLength`, `uplinkChunkSize`. |
| `.streamSettings.xhttpSettings.{sessionIDTable, sessionIDPlacement, sessionIDKey, seqPlacement, seqKey}` | `.transport.{session_id_table, session_placement, session_key, seq_placement, seq_key}` | Строковые ключи; placement: `path`, `cookie`, `header`, `query`. |
| `.streamSettings.xhttpSettings.{uplinkDataPlacement, uplinkDataKey, uplinkHTTPMethod, noGRPCHeader}` | `.transport.{uplink_data_placement, uplink_data_key, uplink_http_method, no_grpc_header}` | Placement: `auto`, `body`, `cookie`, `header`; method: `GET`/`POST`; `noGRPCHeader` — boolean. `GET`, `cookie` и `header` требуют `mode: "packet-up"`. |
| `.streamSettings.xhttpSettings.{xPaddingMethod, xPaddingPlacement, xPaddingKey, xPaddingObfsMode, xPaddingHeader}` | `.transport.{x_padding_method, x_padding_placement, x_padding_key, x_padding_obfs_mode, x_padding_header}` | Method: `repeat-x`/`tokenish`; placement: `cookie`, `header`, `query`, `queryInHeader`; ключ и header — строки, obfs mode — boolean. |
| `.streamSettings.xhttpSettings.xmux.maxConnections` | `.transport.xmux.max_connections` | Необязательное `0`, положительное число или положительный диапазон. |
| `.streamSettings.xhttpSettings.xmux.maxConcurrency` | `.transport.xmux.max_concurrency` | Те же ограничения; нельзя задавать одновременно с положительным `maxConnections`. |
| `.streamSettings.xhttpSettings.xmux.{cMaxReuseTimes, hMaxRequestTimes, hMaxReusableSecs, hKeepAlivePeriod}` | `.transport.xmux.{c_max_reuse_times, h_max_request_times, h_max_reusable_secs, h_keep_alive_period}` | Первые три — число/диапазон (`hMax*` положительны); `hKeepAlivePeriod` — целое `≥ 0`. |
| `.streamSettings.xhttpSettings.downloadSettings` | `.transport.download` | Необязательный клиентский XHTTP: обязательны `address`, `port`, `network: "xhttp"`, `security: "tls"`/`"reality"` и `xhttpSettings.path`; поддерживаются те же клиентские поля, TLS/Reality-политики и проверки. Неизвестные/server-only поля фатальны. |

## Одобренный Reality-контракт

Reality принимается **только** при `streamSettings.security: "reality"` и только как клиентская настройка. Нельзя использовать этот конвертер для серверной Reality-конфигурации.

| Xray path | sing-box-extended path | Статус / проверка |
|---|---|---|
| `.streamSettings.tlsSettings.realitySettings.publicKey` | `.tls.reality.public_key` | Обязателен: base64url без `=`, после декодирования ровно 32 байта. |
| `.streamSettings.tlsSettings.realitySettings.shortId` | `.tls.reality.short_id` | Необязателен: чётное число hex-символов, не более 16. |
| `.streamSettings.tlsSettings.{fingerprint, settings.fingerprint}` либо отсутствие fingerprint | `.tls.utls` | Используется тот же default/проверка uTLS из матрицы: по умолчанию `chrome`, поддерживаются только перечисленные fingerprint и auto-алиасы. |
| Любой иной ключ в `realitySettings` | — | Ошибка. В частности, не принимаются серверные ключи, destination/target, spider-параметры и любые неописанные расширения. |

## Преднамеренные исключения

Не поддерживаются VLESS URI, одиночный outbound или массив вместо объекта с `outbounds`, полный профиль, `detour`, произвольное преобразование Xray transport и иные протоколы. Вложенная клиентская форма `settings.vnext` также не принимается. Локальные верхнеуровневые `inbounds` и routing игнорируются. `enableXmux` — метаданные Xray: не выводится.

Не-VLESS элементы пропускаются с одним итоговым предупреждением. VLESS с неподдерживаемым transport/security также пропускается с предупреждением. Напротив, любая ошибка в выбранном VLESS (обязательное поле, неизвестный ключ, недопустимое значение, конфликт `Host` или XMUX) делает весь результат недоступным.

Серверообразные поля и формы отвергаются: в том числе `listen`, server port `0`, `decryption`, `mux`, TLS `certificate`/`key`, а также XHTTP `scStreamUpServerSecs`, `scMaxBufferedPosts`, `noSSEHeader`, `serverMaxHeaderBytes`, `proxyProtocol`, `sniffing`, `allocation` и `fallback`. Поле `.settings.level` — только метаданные и не выводится.

## Диагностика

Диагностика содержит `severity`, `code`, `path` и `message`; значения конфигурации в неё не вставляются. Сообщения ограничены по числу и детерминированно упорядочены. Если не найдено ни одного поддерживаемого VLESS либо есть фатальная ошибка, `value` равен `null`.

## Приватность

Приложение обрабатывает вставленную конфигурацию локально и само не передаёт её по сети. В нём нет fetch/XHR/WebSocket/beacon, хранилищ браузера, cookie, аналитики, service worker, удалённых шрифтов или CDN-ресурсов; CSP запрещает соединения (`connect-src 'none'`).

Копирование в буфер обмена и скачивание передают данные ОС только после явного действия пользователя. Расширения браузера не входят в эту гарантию. «Очистить» сбрасывает вход, результат, диагностику и созданные object URL.

## Локальная проверка

Из корня репозитория запустите встроенные Node.js-тесты; для соответствия CI используйте Node.js 24:

```bash
node --test tests/converter/converter.test.mjs
```

Для проверки интерфейса запустите статический сервер, а не открывайте файл через `file://`:

```bash
python3 -m http.server 4173 --directory docs/converter
```

Откройте <http://127.0.0.1:4173/>. Это позволяет ES-модулям загружаться в обычном HTTP-контексте.

Для проверки совместимости используйте только закреплённый бинарный релиз `sing-box-1.13.14-extended-2.5.1-linux-amd64.tar.gz`, предварительно сверив SHA-256 `7d5131dbe4283c96bc5cd9549c7372baf620f4db55fef65f10982f0170b75ef2`, затем выполните `sing-box check -c <bundle>`. Успешная проверка синтаксиса не делает bundle рабочим профилем без политики потребителя.
