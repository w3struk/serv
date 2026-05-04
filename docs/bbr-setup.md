# Включение BBR 

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

