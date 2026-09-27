#!/bin/bash
# no_internet_to_network.sh - Elimina la salida a Internet (NAT) de una VLAN.
# Uso: ./no_internet_to_network.sh <VLAN_ID> <CIDR>
VLAN_ID="$1"
CIDR="$2"
GW_IF="gw_vlan${VLAN_ID}"
EXT_IF=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')

sudo iptables -t nat -D POSTROUTING -s "$CIDR" -o "$EXT_IF" -j MASQUERADE
sudo iptables -D FORWARD -i "$GW_IF" -o "$EXT_IF" -j ACCEPT

echo "[DONE] Salida a Internet eliminada para VLAN $VLAN_ID ($CIDR)."

