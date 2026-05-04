#!/bin/bash
set -e

echo "Setting up firewall rules..."

iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

iptables -A INPUT -p tcp --dport 22 -j ACCEPT

iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p udp --dport 80 -j ACCEPT

iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT

iptables -A INPUT -p udp --dport 56000 -j ACCEPT

iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

iptables -P INPUT DROP

mkdir -p /etc/network
iptables-save > /etc/network/iptables.rules

echo "Firewall configured"
echo "Rules saved to /etc/network/iptables.rules"