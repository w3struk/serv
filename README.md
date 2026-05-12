# 3x-ui + Caddy + VLESS + XHTTP + TLS — полная схема проксирования


## Настройка сервера

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
<summary>Установка Docker</summary>

Инструкции: https://docs.docker.com/engine/install/

**Быстрая установка:**
```bash
bash <(wget -qO- https://get.docker.com)
```

### Запуск Docker без root

```bash
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
git clone https://github.com/w3struk/steal-oneself /opt
cd /opt/serv
./setup.sh
```

Скрипт интерактивно запросит **домен**.

Скрипт автоматически:
- Генерирует пароль для Lampac
- Включает BBR
- Генерирует случайные пути для панели и подписки
- Обновляет Caddyfile (домен, пути, bcrypt хэш)
- Настраивает firewall (iptables)
- Запускает контейнеры

> [!NOTE]
> Скрипт запускается от root, так как настраивает BBR и firewall.

### Первый вход в панель

1. Откройте URL из вывода скрипта (обязательно со слэшем на конце)
2. Basic Auth (от Caddy): логин `admin`, ваш пароль
3. Страница входа 3x-ui: логин `admin`, пароль `admin`

> [!WARNING]
> Сразу измените стандартные логин и пароль: `Panel Settings -> Authentication`.
> Установите `Panel Listening IP` на `127.0.0.1`.

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

### Настройка подписки

1. `Panel Settings → Subscription → URI Path (sub)`: измените `/sub/` на путь из вывода скрипта (например `/sub-abc123/`)
2. `Panel Settings → Subscription → Reverse Proxy URI`: установите `https://mydomain.com/sub-abc123/`
3. Сохраните и перезапустите панель

## Благодарности

- [Akiyamov](https://github.com/Akiyamov/xray-vps-setup) — xray-vps-setup
- [MHSanaei](https://github.com/MHSanaei/3x-ui) — 3x-ui
- [Lampac NextGen](https://github.com/lampac-nextgen/lampac)
- [CHIZI-0618](https://github.com/CHIZI-0618/) — AndroidTProxyShell
- https://eikeidev.github.io/vless-xtls-converter/

## полезное


```bash
docker ps #список контейнеров
docker compose up -d    # start
docker compose down     # stop
docker compose logs -f  # logs
docker system prune -a
docker compose logs --tail 1000 lampac #Показать последние 1000 строк лога
docker volume ls
docker exec -it lampac bash
docker compose down && docker compose up -d && docker compose logs -f
docker system prune -a --volumes - Очистить все данные (контейнеры, образы, тома)

docker exec -it 3xui_app /app/x-ui setting -webBasePath /admin-izj0/
docker restart 3xui_app
```