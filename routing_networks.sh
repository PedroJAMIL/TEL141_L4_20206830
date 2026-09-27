#!/bin/bash
# routing_networks.sh - Habilita el enrutamiento entre dos VLANs.
# Uso: ./routing_networks.sh <VLAN_ID_1> <VLAN_ID_2>
# Ejemplo: ./routing_networks.sh 100 200

VLAN1="$1"
VLAN2="$2"
GW1="gw_vlan${VLAN1}"
GW2="gw_vlan${VLAN2}"

# Permitir el reenvío en ambos sentidos entre las dos VLANs
sudo iptables -A FORWARD -i "$GW1" -o "$GW2" -j ACCEPT
sudo iptables -A FORWARD -i "$GW2" -o "$GW1" -j ACCEPT

echo "[DONE] Enrutamiento habilitado entre VLAN $VLAN1 y VLAN $VLAN2."
