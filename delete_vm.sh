#!/bin/bash
# delete_vm.sh - Elimina una VM y sus recursos asociados.
# Uso: ./delete_vm.sh <NOMBRE_VM> <NOMBRE_OVS> <VLAN_ID> <PUERTO_VNC>
# Ejemplo: ./delete_vm.sh vm100 br-int 100 5901

VM_NAME="$1"
BRIDGE="$2"
VLAN_ID="$3"
VNC_PORT="$4"

BASE_IMG="cirros-0.5.1-x86_64-disk.img"
DISK="${VM_NAME}.qcow2"
TAP="${VM_NAME}_tap"

# 1. Matar el proceso QEMU de esta VM (identificado por su disco)
PID=$(sudo pgrep -f "qemu-system-x86_64.*${DISK}")
if [ -n "$PID" ]; then
    sudo kill "$PID"
    echo "[OK] Proceso QEMU $PID de $VM_NAME detenido."
else
    echo "[INFO] No se encontró proceso QEMU para $VM_NAME."
fi
sleep 1   # dar tiempo a que libere el disco

# 2. Quitar la TAP del OVS y del sistema
sudo ovs-vsctl --if-exists del-port "$BRIDGE" "$TAP"
sudo ip link del "$TAP" 2>/dev/null
echo "[OK] TAP $TAP eliminada."

# 3. Borrar el disco diferencial de la VM
rm -f "$DISK"
echo "[OK] Disco $DISK eliminado."

# 4. Si la imagen base ya no tiene deltas (ninguna otra .qcow2 la usa), eliminarla
if [ -f "$BASE_IMG" ]; then
    EN_USO=0
    for img in *.qcow2; do
        [ -e "$img" ] || continue
        if qemu-img info "$img" 2>/dev/null | grep -q "backing file:.*${BASE_IMG}"; then
            EN_USO=1
            break
        fi
    done
    if [ "$EN_USO" -eq 0 ]; then
        rm -f "$BASE_IMG"
        echo "[OK] Imagen base $BASE_IMG eliminada (sin deltas restantes)."
    else
        echo "[INFO] Imagen base conservada (aún hay VMs que la usan)."
    fi
fi

echo "[DONE] delete_vm.sh completado."
