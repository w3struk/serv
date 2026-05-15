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
</details>

### Развёртывание

```bash
cd /opt && git clone https://github.com/w3struk/serv && cd /serv

./setup.sh
./setup.sh add-client
./setup.sh status
./setup.sh help
```

Скрипт автоматически:
- Генерирует пароль для Lampac
- Генерирует случайные пути для панели и подписки
- Обновляет Caddyfile (домен, пути, bcrypt хэш)
- Запускает контейнеры

> [!NOTE]
> Скрипт запускается от root, так как настраивает BBR и firewall.

## Полезное

```bash
docker compose down && docker compose up -d && docker compose logs -f # start, stop, logs
docker compose down 3xui && docker pull ghcr.io/mhsanaei/3x-ui:latest && docker compose up -d 3xui #update 3x-ui
docker ps #список контейнеров
docker system prune -a  # clear all data
docker volume ls
docker exec -it lampac bash
```

## Благодарности

- [Akiyamov](https://github.com/Akiyamov/xray-vps-setup) — xray-vps-setup
- [MHSanaei](https://github.com/MHSanaei/3x-ui) — 3x-ui
- [Lampac NextGen](https://github.com/lampac-nextgen/lampac)
- https://eikeidev.github.io/vless-xtls-converter/