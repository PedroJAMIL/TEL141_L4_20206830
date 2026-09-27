#!/bin/bash
# internet_to_network.sh - Habilita salida a Internet (NAT) para una VLAN.
# Uso: ./internet_to_network.sh <VLAN_ID> <CIDR>
VLAN_ID="$1"
CIDR="$2"
GW_IF="gw_vlan${VLAN_ID}"
EXT_IF=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')

sudo iptables -t nat -A POSTROUTING -s "$CIDR" -o "$EXT_IF" -j MASQUERADE
sudo iptables -A FORWARD -i "$GW_IF" -o "$EXT_IF" -j ACCEPT
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "[DONE] Salida a Internet habilitada para VLAN $VLAN_ID ($CIDR) vía $EXT_IF."
