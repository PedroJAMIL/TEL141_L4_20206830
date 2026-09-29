#!/bin/bash
# create_network_vlan.sh - Crea una red VLAN en el OVS con gateway y (opcional) DHCP.
# Uso: ./create_network_vlan.sh <VLAN_ID> <CIDR> <yes|no> [ini,fin]
# Con DHCP:  ./create_network_vlan.sh 100 192.168.0.0/24 yes 192.168.0.11,192.168.0.15
# Sin DHCP:  ./create_network_vlan.sh 200 192.168.2.0/24 no
#
# Cambios respecto a la versión del IP (para correrlo remoto y con 2 VLANs a la vez):
#  - apt-get no interactivo y sin leer stdin (con 'bash -s' el stdin ES el script)
#  - cada dnsmasq con su propio pid-file y leasefile (antes compartían los mismos)
#  - --conf-file=/dev/null para ignorar /etc/dnsmasq.conf del sistema
#  - opción 6 (DNS) para que los clientes resuelvan nombres al salir a Internet

BRIDGE="br-int"
VLAN_ID="$1"
CIDR="$2"
DHCP="$3"
RANGO="$4"

# Calcular direcciones desde el CIDR (primera = gateway, segunda = servidor DHCP)
GATEWAY=$(python3 -c "import ipaddress,sys; n=ipaddress.ip_network(sys.argv[1],strict=False); print(n.network_address+1)" "$CIDR")
DHCP_IP=$(python3 -c "import ipaddress,sys; n=ipaddress.ip_network(sys.argv[1],strict=False); print(n.network_address+2)" "$CIDR")
PREFIX=$(python3 -c "import ipaddress,sys; n=ipaddress.ip_network(sys.argv[1],strict=False); print(n.prefixlen)" "$CIDR")
NETMASK=$(python3 -c "import ipaddress,sys; n=ipaddress.ip_network(sys.argv[1],strict=False); print(n.netmask)" "$CIDR")

GW_IF="gw_vlan${VLAN_ID}"

# 1. Interfaz interna = gateway de la VLAN (primera dirección de la red)
sudo ovs-vsctl add-port "$BRIDGE" "$GW_IF" tag="$VLAN_ID" -- set interface "$GW_IF" type=internal
sudo ip addr add "${GATEWAY}/${PREFIX}" dev "$GW_IF"
sudo ip link set dev "$GW_IF" up
echo "[OK] Gateway VLAN $VLAN_ID: ${GATEWAY}/${PREFIX} en $GW_IF"

# 2. Si DHCP habilitado -> namespace + dnsmasq
if [ "$DHCP" == "yes" ]; then
    # asegurar dnsmasq instalado y sin el servicio del sistema estorbando
    which dnsmasq >/dev/null 2>&1 || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq </dev/null
    sudo systemctl stop dnsmasq 2>/dev/null; sudo systemctl disable dnsmasq 2>/dev/null

    NS="ns-dhcp-vlan${VLAN_ID}"
    DHCP_IF="dhcp_v${VLAN_ID}"
    RANGO_INI=$(echo "$RANGO" | cut -d',' -f1)
    RANGO_FIN=$(echo "$RANGO" | cut -d',' -f2)

    sudo ip netns add "$NS"
    sudo ovs-vsctl add-port "$BRIDGE" "$DHCP_IF" tag="$VLAN_ID" -- set interface "$DHCP_IF" type=internal
    sudo ip link set "$DHCP_IF" netns "$NS"
    sudo ip netns exec "$NS" ip addr add "${DHCP_IP}/${PREFIX}" dev "$DHCP_IF"
    sudo ip netns exec "$NS" ip link set "$DHCP_IF" up
    sudo ip netns exec "$NS" ip link set lo up

    # dnsmasq solo DHCP (--port=0 desactiva DNS); opción 3 = default gateway, 6 = DNS
    sudo ip netns exec "$NS" dnsmasq \
        --conf-file=/dev/null \
        --interface="$DHCP_IF" --bind-interfaces --port=0 \
        --pid-file="/run/dnsmasq-vlan${VLAN_ID}.pid" \
        --dhcp-leasefile="/var/lib/misc/dnsmasq-vlan${VLAN_ID}.leases" \
        --dhcp-range="${RANGO_INI},${RANGO_FIN},${NETMASK},12h" \
        --dhcp-option=3,"$GATEWAY" \
        --dhcp-option=6,8.8.8.8 </dev/null
    echo "[OK] DHCP en $NS: servidor ${DHCP_IP}, rango ${RANGO_INI}-${RANGO_FIN}, gw ${GATEWAY}"
else
    echo "[INFO] VLAN $VLAN_ID creada sin DHCP."
fi

echo "[DONE] create_network_vlan.sh completado."
