# Настройка SSH 

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
