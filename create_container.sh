#!/bin/bash
# create_container.sh - Crea un contenedor conectado a una VLAN del OVS mediante un par veth
# y le pide IP por DHCP. Se ejecuta en el worker (Server 1), lanzado desde el Server 4.
# Uso: ./create_container.sh <NOMBRE> <NOMBRE_OVS> <VLAN_ID>
# Ejemplo: ./create_container.sh ct100 br-int 100
#
# Usa Docker (imagen alpine, --network none). Si Docker no está o no puede bajar la imagen,
# cae a un Linux Network Namespace con el mismo nombre (mismo efecto de red).

NAME="$1"
BRIDGE="$2"
VLAN_ID="$3"
STATIC_IP="$4"
STATIC_GW="$5"
IMG="alpine"
VETH_OVS="${NAME}_ovs"   # extremo que va al OVS
VETH_CT="${NAME}_ct"     # extremo que entra al contenedor (se renombra a eth0)

# 1. Crear el contenedor sin red (o namespace como respaldo)
MODE="netns"
if command -v docker >/dev/null 2>&1; then
    sudo docker image inspect "$IMG" >/dev/null 2>&1 || sudo docker pull -q "$IMG" </dev/null
    if sudo docker run -d --name "$NAME" --hostname "$NAME" --label tel141=lab4 \
           --network none --cap-add NET_ADMIN "$IMG" sleep infinity </dev/null >/dev/null; then
        MODE="docker"
    fi
fi

if [ "$MODE" == "docker" ]; then
    PID=$(sudo docker inspect -f '{{.State.Pid}}' "$NAME")
    NSRUN="sudo nsenter -t $PID -n"
    echo "[OK] Contenedor Docker $NAME creado (PID $PID)."
else
    sudo ip netns add "$NAME"
    sudo mkdir -p "/etc/netns/$NAME"                       # resolv.conf propio: dhclient no toca el del host
    echo "nameserver 8.8.8.8" | sudo tee "/etc/netns/$NAME/resolv.conf" >/dev/null
    NSRUN="sudo ip netns exec $NAME"
    echo "[WARN] Docker no disponible: $NAME creado como network namespace."
fi

# 2. Par veth: un extremo al OVS con tag de VLAN, el otro dentro del contenedor
sudo ip link add "$VETH_OVS" type veth peer name "$VETH_CT"
sudo ovs-vsctl add-port "$BRIDGE" "$VETH_OVS" tag="$VLAN_ID"
sudo ip link set "$VETH_OVS" up
if [ "$MODE" == "docker" ]; then
    sudo ip link set "$VETH_CT" netns "$PID"
else
    sudo ip link set "$VETH_CT" netns "$NAME"
fi
$NSRUN ip link set "$VETH_CT" name eth0
$NSRUN ip link set eth0 up
$NSRUN ip link set lo up
echo "[OK] veth $VETH_OVS (OVS, VLAN $VLAN_ID) <-> eth0 ($NAME)."

# 3. Pedir IP por DHCP al dnsmasq de su VLAN (Server 3)
if [ -n "$STATIC_IP" ]; then
    $NSRUN ip addr add "$STATIC_IP" dev eth0
    $NSRUN ip route replace default via "$STATIC_GW"
    echo "[OK] IP estática $STATIC_IP, gateway $STATIC_GW."
elif [ "$MODE" == "docker" ]; then
    sudo docker exec "$NAME" udhcpc -i eth0 -t 5 -T 2 -n -q </dev/null
else
    sudo ip netns exec "$NAME" dhclient -1 -pf "/run/dhclient-$NAME.pid" \
        -lf "/var/lib/dhcp/dhclient-$NAME.leases" eth0 </dev/null
fi

IP=$($NSRUN ip -4 -o addr show eth0 | awk '{print $4}')
if [ -n "$IP" ]; then
    echo "[DONE] $NAME listo: eth0 = $IP (VLAN $VLAN_ID)."
else
    echo "[ERROR] $NAME no obtuvo IP por DHCP. Revisa dnsmasq en Server 3 y el OFS."
    exit 1
fi
