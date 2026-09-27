#!/bin/bash
# create_vm.sh - Crea y lanza una VM conectada a una VLAN del OVS.
# Uso: ./create_vm.sh <NOMBRE_VM> <NOMBRE_OVS> <VLAN_ID> <PUERTO_VNC>
# Ejemplo: ./create_vm.sh vm100 br-int 100 5901

VM_NAME="$1"
BRIDGE="$2"
VLAN_ID="$3"
VNC_PORT="$4"

BASE_IMG="cirros-0.5.1-x86_64-disk.img"
BASE_URL="http://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img"
DISK="${VM_NAME}.qcow2"
TAP="${VM_NAME}_tap"

# Calcular el display VNC (qemu usa :N, donde puerto = 5900 + N)
if [ "$VNC_PORT" -ge 5900 ]; then
    DISPLAY_N=$((VNC_PORT - 5900))
else
    DISPLAY_N="$VNC_PORT"
fi

# MAC basada en el código PUCP (20:20:68:30) + display + 00
MAC=$(printf "20:20:68:30:%02x:00" "$DISPLAY_N")

# 1. Disco de arranque: detectar imagen base; si no existe, descargarla
if [ ! -f "$BASE_IMG" ]; then
    echo "[INFO] Imagen base no encontrada. Descargando..."
    wget -q "$BASE_URL" -O "$BASE_IMG"
fi

# Crear imagen diferencial para esta VM
qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$DISK"
echo "[OK] Disco $DISK creado (backing: $BASE_IMG)."

# 2. Crear la interfaz TAP y conectarla a la VLAN en el OVS
sudo ip tuntap add mode tap name "$TAP"
sudo ovs-vsctl add-port "$BRIDGE" "$TAP" tag="$VLAN_ID"
sudo ip link set dev "$TAP" up
echo "[OK] TAP $TAP conectada a $BRIDGE (VLAN $VLAN_ID)."

# 3. Lanzar la VM con QEMU
sudo qemu-system-x86_64 -enable-kvm \
    -vnc "0.0.0.0:${DISPLAY_N}" \
    -netdev "tap,id=net0,ifname=${TAP},script=no,downscript=no" \
    -device "e1000,netdev=net0,mac=${MAC}" \
    -daemonize "$DISK"
echo "[DONE] VM $VM_NAME lanzada (VNC :$DISPLAY_N, MAC $MAC)."
