#!/bin/bash
# init_master.sh - Inicializa el nodo master (Server 3).
# Uso: ./init_master.sh <interfaz1> [interfaz2] ...
# Ejemplo: ./init_master.sh ens4

BRIDGE="br-int"

# 1. Crear el OVS br-int si no existe
if ! sudo ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    sudo ovs-vsctl add-br "$BRIDGE"
    echo "[OK] Bridge $BRIDGE creado."
else
    echo "[INFO] Bridge $BRIDGE ya existe."
fi

# 2. Conectar las interfaces provistas como parámetro al bridge
for iface in "$@"; do
    if ! sudo ovs-vsctl list-ports "$BRIDGE" | grep -qx "$iface"; then
        sudo ovs-vsctl add-port "$BRIDGE" "$iface"
        echo "[OK] Interfaz $iface conectada a $BRIDGE."
    else
        echo "[INFO] Interfaz $iface ya está en $BRIDGE."
    fi
done

# 3. Activar IPv4 forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# 4. Cambiar la política por defecto de la cadena FORWARD a DROP
sudo iptables -P FORWARD DROP

echo "[DONE] init_master.sh completado."
