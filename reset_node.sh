#!/bin/bash
# reset_node.sh - Deja un nodo limpio antes de desplegar (restos del lab 3 o de otra actividad).
# Se ejecuta en cada server, lanzado desde el Server 4.
# Uso: ./reset_node.sh <master|worker>

ROLE="$1"
BRIDGE="br-int"

# 1. VMs QEMU
sudo pkill -f '[q]emu-system-x86_64' && sleep 1 && echo "[OK] VMs QEMU detenidas."

# 2. Contenedores creados por create_container.sh
if command -v docker >/dev/null 2>&1; then
    IDS=$(sudo docker ps -aq --filter label=tel141=lab4)
    [ -n "$IDS" ] && sudo docker rm -f $IDS >/dev/null && echo "[OK] Contenedores eliminados."
fi

# 3. dnsmasq de las VLANs y clientes DHCP de los namespaces
sudo pkill -f '[d]nsmasq.*dhcp_v' && echo "[OK] dnsmasq de VLANs detenidos."
sudo pkill -f '[d]hclient.*dhclient-ct' 2>/dev/null

# 4. Namespaces (del DHCP y de contenedores de respaldo)
for ns in $(ip netns list | awk '{print $1}'); do
    sudo ip netns del "$ns" && echo "[OK] netns $ns eliminado."
    sudo rm -rf "/etc/netns/$ns"
done

# 5. OVS br-int (se lleva sus puertos internos: gw_vlanX, dhcp_vX)
sudo ovs-vsctl --if-exists del-br "$BRIDGE" && echo "[OK] $BRIDGE eliminado."

# 6. veth y TAP sueltos (no toca los veth de docker0)
for ifc in $(ip -o link show type veth | grep -v 'master docker0' | awk -F': ' '{print $2}' | cut -d@ -f1); do
    sudo ip link del "$ifc" 2>/dev/null && echo "[OK] veth $ifc eliminado."
done
for ifc in $(ip -o link show | awk -F': ' '{print $2}' | grep '_tap$'); do
    sudo ip link del "$ifc" 2>/dev/null && echo "[OK] TAP $ifc eliminada."
done

# 7. Discos diferenciales de VMs (la imagen base .img se conserva para no volver a descargarla)
rm -f "$HOME"/*.qcow2

# 8. Solo en el head node: reglas iptables del lab y leases
if [ "$ROLE" == "master" ]; then
    # Ojo: limpia FORWARD y POSTROUTING completos (este nodo no usa Docker para el lab)
    sudo iptables -F FORWARD
    sudo iptables -t nat -F POSTROUTING
    sudo rm -f /var/lib/misc/dnsmasq-vlan*.leases
    echo "[OK] Reglas iptables FORWARD/NAT limpiadas."
fi

echo "[DONE] reset_node.sh ($ROLE) completado en $(hostname)."
