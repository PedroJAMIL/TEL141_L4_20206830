#!/bin/bash
# init_worker.sh - Inicializa un nodo worker (Servers 1/2).
# Uso: ./init_worker.sh <interfaz1> [interfaz2] ...
# Ejemplo: ./init_worker.sh ens4

BRIDGE="br-int"

# 1. Crear el OVS br-int si no existe
if ! sudo ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    sudo ovs-vsctl add-br "$BRIDGE"
    echo "[OK] Bridge $BRIDGE creado."
else
    echo "[INFO] Bridge $BRIDGE ya existe."
fi

# 2. Conectar las interfaces provistas al bridge
for iface in "$@"; do
    if ! sudo ovs-vsctl list-ports "$BRIDGE" | grep -qx "$iface"; then
        sudo ovs-vsctl add-port "$BRIDGE" "$iface"
        echo "[OK] Interfaz $iface conectada a $BRIDGE."
    else
        echo "[INFO] Interfaz $iface ya está en $BRIDGE."
    fi
done

echo "[DONE] init_worker.sh completado."
