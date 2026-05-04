# Установка Docker 

### Установка

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
