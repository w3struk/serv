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
cd /opt && git clone https://github.com/w3struk/serv && cd /serv
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

## Благодарности

- [Akiyamov](https://github.com/Akiyamov/xray-vps-setup) — xray-vps-setup
- [MHSanaei](https://github.com/MHSanaei/3x-ui) — 3x-ui
- [Lampac NextGen](https://github.com/lampac-nextgen/lampac)
- https://eikeidev.github.io/vless-xtls-converter/

## полезное

```bash
docker ps #список контейнеров
docker compose up -d    # start
docker compose down     # stop
docker compose logs -f  # logs
docker system prune -a  # clear all data
docker volume ls
docker exec -it lampac bash
docker compose down && docker compose up -d && docker compose logs -f
```