#!/bin/bash
# no_routing_networks.sh - Elimina el enrutamiento entre dos VLANs.
# Uso: ./no_routing_networks.sh <VLAN_ID_1> <VLAN_ID_2>
# Ejemplo: ./no_routing_networks.sh 100 200

VLAN1="$1"
VLAN2="$2"
GW1="gw_vlan${VLAN1}"
GW2="gw_vlan${VLAN2}"

# Eliminar las mismas reglas (-D)
sudo iptables -D FORWARD -i "$GW1" -o "$GW2" -j ACCEPT
sudo iptables -D FORWARD -i "$GW2" -o "$GW1" -j ACCEPT

echo "[DONE] Enrutamiento eliminado entre VLAN $VLAN1 y VLAN $VLAN2."
