# Настройка сервера

### Подготовка

- Зарегистрирован и делегирован домен (например, `mydomain.com`), указывающий на ваш VPS

<details>
<summary>Настройка SSH</summary>

См. [docs/ssh-setup.md](../docs/ssh-setup.md)

</details>

<details>
<summary>Включение BBR</summary>

См. [docs/bbr-setup.md](../docs/bbr-setup.md)

</details>

### Установка Docker

См. [docs/docker-install.md](../docs/docker-install.md)

### Развёртывание

```bash
cd /opt
git clone --depth 1 https://github.com/w3struk/steal-oneself serv
mv serv/server/* serv/
rm -rf serv/server serv/client serv/docs
cd serv
```

#### Подготовка паролей

**Пароль для Lampac NextGen:**
```bash
printf '%s' 'your_strong_password' > ./lampac/passwd
```

**Пароль для Caddy (bcrypt-хэш):**
```bash
docker run --rm -it caddy caddy hash-password
```
Введите пароль и скопируйте полученный хэш (начинается с `$2a$`).

#### Настройка домена

Замените `example.com` на ваш реальный домен:

```bash
sed -i 's/example.com/mydomain.com/g' ./Caddyfile
```

Или используйте автоматический скрипт:
```bash
bash ./scripts/setup.sh mydomain.com
```

#### Запуск

```bash
docker compose up -d
```

#### Настройка пути до панели

При первом запуске панель ожидает корень `/`, а Caddy проксирует путь `/admin`. Установите правильный путь:

```bash
docker exec -it 3xui_app /app/x-ui setting -webBasePath /admin-secret-path/
docker restart 3xui_app
```

#### Первый вход в панель

1. Откройте `https://mydomain.com/admin-secret-path/` (обязательно со слэшем на конце)
2. Basic Auth (от Caddy): логин `admin`, ваш пароль
3. Страница входа 3x-ui: логин `admin`, пароль `admin`

> [!WARNING]
> Сразу измените стандартные логин и пароль: `Panel Settings -> Authentication`.
> Установите `Panel Listening IP` на `127.0.0.1`.

#### Настройка пути до подписки

1. `Panel Settings → Subscription → URI Path (sub)`: измените `/sub/` на `/sub-secret-path/`
2. `Panel Settings → Subscription → Reverse Proxy URI`: установите `https://mydomain.com/sub-secret-path/`
3. Сохраните и перезапустите панель

> [!CAUTION]
> Если `URI Path` не начинается с `sub`, измените путь `/sub*` в `Caddyfile`:
> ```bash
> sed -i 's|/sub|/super-secret-path|g' ./Caddyfile
> ```

Перезапуск после изменений:
```bash
docker compose down && docker compose up -d
```

> [!CAUTION]
> Используйте уникальные значения для `admin-secret-path` и `sub-secret-path`.

### Создание inbounds

#### VLESS + XHTTP за Caddy

- **Protocol:** VLESS
- **Listen IP:** `127.0.0.1`
- **Port:** `2023`
- **Transmission:** XHTTP
- **Security:** none
- **XHTTP Mode:** auto
- **XHTTP Path:** `/api/v*` (свой уникальный path)
- **Sniffing:** enable — HTTP, TLS, QUIC, FAKEDNS

**External Proxy:**
- **Dest/Domain/IP:** `mydomain.com`
- **Port:** `443`
- **Force TLS:** включить
- **Remark:** `Через Caddy`

#### Standalone VK TURN (VLESS Mode)

- **Protocol:** VLESS
- **Listen IP:** `127.0.0.1`
- **Port:** `2024` (должен совпадать с `CONNECT_ADDR` в `docker-compose.yml`)
- **Transmission:** TCP
- **Security:** none
- **Sniffing:** enable

### Настройка firewall

```bash
sudo bash ./scripts/firewall.sh
```

Или вручную:
```bash
sudo iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 56000 -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -P INPUT DROP
sudo iptables-save > /etc/network/iptables.rules
```