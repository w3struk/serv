# Настройка сервера

### Подготовка

- Зарегистрирован и делегирован домен (например, `mydomain.com`), указывающий на ваш VPS

<details>
<summary>Настройка SSH</summary>


Выполняется на локальном компьютере (GNU/Linux или Windows). На Windows используйте PowerShell.

### Генерация ключа

```bash
ssh-keygen -t ed25519
```

При выполнении вам предложат изменить место хранения ключа и добавить пароль. Менять локацию не надо, пароль добавьте для безопасности.

### Копирование публичного ключа на VPS

**Linux:**
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub ваш_пользователь@ваша_vps
```

**Windows (PowerShell):**
```powershell
ssh-copy-id -i $env:USERPROFILE\.ssh\id_ed25519.pub ваш_пользователь@ваша_vps
```

Если `ssh-copy-id` не работает на Windows:
```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ваш_пользователь@ваша_vps "cat >> .ssh/authorized_keys"
```

### Отключение входа по паролю

Создайте файл конфигурации:
```bash
sudo nano /etc/ssh/sshd_config.d/00-disable-password.conf
```

Добавьте:
```
Port 22
PasswordAuthentication no
```

Перезапустите SSH:
```bash
sudo systemctl restart ssh
```
</details>

<details>
<summary>Включение BBR</summary>

BBR — алгоритм управления перегрузкой TCP от Google, улучшающий производительность сети.

```bash
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Проверка:
```bash
sysctl net.ipv4.tcp_congestion_control
# Должно вывести: net.ipv4.tcp_congestion_control = bbr
```
</details>
<details>
<summary>Установка Docker</summary>

Инструкции: https://docs.docker.com/engine/install/

**Быстрая установка:**
```bash
bash <(wget -qO- https://get.docker.com) @ -o get-docker.sh
```

### Запуск Docker без root

```bash
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
```

### Проверка

```bash
docker run hello-world
```
</details>

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

### Настройка firewall

```bash
sudo iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 443 -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -P INPUT DROP
sudo iptables-save > /etc/network/iptables.rules
```