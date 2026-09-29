#!/bin/bash
# DEV/actividad_3/script.sh - ACTIVIDAD 3: redes aisladas (VLAN 100 y 200) con DHCP y SIN salida a Internet.
# Script principal. Se ejecuta SOLO en el Server 4 (rol Cliente); todo lo demás va por SSH:
#     ssh user@ip 'bash -s' < ./script.sh "param1" "param2"
#
# Uso: ./DEV/actividad_3/script.sh            -> limpia, despliega y verifica
#      ./DEV/actividad_3/script.sh deploy     -> solo limpia y despliega
#      ./DEV/actividad_3/script.sh verify     -> solo pruebas (evidencias)
#      ./DEV/actividad_3/script.sh clean      -> deja los 3 servers limpios
#
# Diferencia con la Actividad 1: NO se ejecuta internet_to_network.sh (sin NAT por ens3).
# Con FORWARD en DROP y sin reglas, el tráfico no sale de su VLAN ni hacia Internet.
#
# Roles:  Server 3 = Head Node (gateways, DHCP, iptables)
#         Server 1 = Cómputo (contenedores)   Server 2 = Cómputo (VMs)

DIR="$(cd "$(dirname "$0")" && pwd)"      # carpeta de la actividad (aquí queda el log)
ROOT="$(cd "$DIR/../.." && pwd)"          # raíz del repo (scripts base)
USR="ubuntu"
S1="10.0.10.1"; S2="10.0.10.2"; S3="10.0.10.3"; OFS="10.0.10.5"
DATA_IF="ens4"
BR="br-int"

V1=100; NET1="192.168.0.0/24"; RANGE1="192.168.0.10,192.168.0.50"
V2=200; NET2="192.168.2.0/24"; RANGE2="192.168.2.10,192.168.2.50"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
LOG="$DIR/act3_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
PASS=0; FAILS=0

# ---------- helpers ----------
# run <ip> <script> [args...]  -> ejecuta un script local en el nodo remoto
run() {
    local ip="$1" sc="$2"; shift 2
    echo -e "\n>>> [$ip] $sc $*" >&2
    ssh "${SSH_OPTS[@]}" "$USR@$ip" 'bash -s' "$@" < "$ROOT/$sc"
}
# cmd <ip> "<comando>"  -> comando suelto en el nodo remoto
cmd() {
    local ip="$1"; shift
    echo -e "\n>>> [$ip] $*" >&2
    ssh -n "${SSH_OPTS[@]}" "$USR@$ip" "$@"
}
# ct_exec <contenedor> "<comando>"  -> comando dentro de un contenedor del Server 1
ct_exec() {
    local name="$1"; shift
    echo -e "\n>>> [$S1:$name] $*" >&2
    ssh "${SSH_OPTS[@]}" "$USR@$S1" 'bash -s' "$name" "'$*'" <<'EOF'
if sudo docker inspect "$1" >/dev/null 2>&1; then sudo docker exec "$1" sh -c "$2"
else sudo ip netns exec "$1" sh -c "$2"; fi
EOF
}
# test_ping <contenedor> <destino> <ok|fail> <descripción>
test_ping() {
    local ct="$1" dst="$2" exp="$3" desc="$4" res="fail"
    if [ -z "$dst" ]; then echo "[FAIL] $ct -> ? ($desc): no hay IP destino"; FAILS=$((FAILS+1)); return; fi
    ct_exec "$ct" "ping -c 2 -W 2 $dst" && res="ok"
    if [ "$res" == "$exp" ]; then
        echo "[PASS] $ct -> $dst ($desc): $res"; PASS=$((PASS+1))
    else
        echo "[FAIL] $ct -> $dst ($desc): $res, se esperaba $exp"; FAILS=$((FAILS+1))
    fi
}
ct_ip() { ct_exec "$1" "ip -4 -o addr show eth0" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tail -1; }
vm_ip() { # vm_ip <MAC>  -> IP entregada por dnsmasq (Server 3)
    cmd "$S3" "sudo cat /var/lib/misc/dnsmasq-vlan*.leases 2>/dev/null" 2>/dev/null | grep -i "$1" | awk '{print $3}' | tail -1
}

# ---------- 0. prechequeo ----------
precheck() {
    for f in init_master.sh init_worker.sh create_network_vlan.sh \
             create_vm.sh create_container.sh reset_node.sh; do
        [ -f "$ROOT/$f" ] || { echo "[ERROR] Falta $f en $ROOT"; exit 1; }
    done
    for ip in $S1 $S2 $S3; do
        if ! ssh -n "${SSH_OPTS[@]}" "$USR@$ip" 'sudo -n true' 2>/dev/null; then
            echo "[ERROR] $ip: sin SSH passwordless o sin sudo NOPASSWD. Ejecuta ./setup_ssh.sh"; exit 1
        fi
    done
    echo "[OK] SSH passwordless + sudo NOPASSWD en server1, server2, server3."
}

clean() {
    echo -e "\n========== LIMPIEZA =========="
    run "$S1" reset_node.sh worker
    run "$S2" reset_node.sh worker
    run "$S3" reset_node.sh master
}

deploy() {
    clean

    echo -e "\n========== 1. HEAD NODE (Server 3) =========="
    cmd "$S3" "sudo ip link set $DATA_IF up"
    run "$S3" init_master.sh "$DATA_IF"

    echo -e "\n========== 2. WORKERS (Server 1 y 2) =========="
    for ip in $S1 $S2; do
        cmd "$ip" "sudo ip link set $DATA_IF up"
        run "$ip" init_worker.sh "$DATA_IF"
    done

    echo -e "\n========== 3. REDES VLAN + DHCP (Server 3) =========="
    run "$S3" create_network_vlan.sh "$V1" "$NET1" yes "$RANGE1"
    run "$S3" create_network_vlan.sh "$V2" "$NET2" yes "$RANGE2"

    # 4. SIN salida a Internet: no se ejecuta internet_to_network.sh
    #    Redes AISLADAS: no se ejecuta routing_networks.sh

    echo -e "\n========== 4. CÓMPUTO =========="
    run "$S1" create_container.sh ct100 "$BR" "$V1"
    run "$S1" create_container.sh ct200 "$BR" "$V2"
    run "$S2" create_vm.sh vm100 "$BR" "$V1" 5901
    run "$S2" create_vm.sh vm200 "$BR" "$V2" 5902
}

verify() {
    echo -e "\n========== 5. VERIFICACIÓN =========="
    cmd "$OFS" 'for b in $(sudo ovs-vsctl list-br); do sudo ovs-vsctl show; sudo ovs-ofctl dump-flows $b; done' || true
    cmd "$S3" "sudo ovs-vsctl show; ip -br addr show | grep gw_vlan; ip netns list; pgrep -a dnsmasq"
    cmd "$S3" "sudo iptables -S FORWARD; sudo iptables -t nat -S POSTROUTING; sysctl net.ipv4.ip_forward"
    cmd "$S1" "sudo ovs-vsctl show"
    cmd "$S2" "sudo ovs-vsctl show; pgrep -a qemu-system"

    echo -e "\nEsperando 45 s a que las VMs cirros arranquen y pidan IP por DHCP..."
    sleep 45
    cmd "$S3" "sudo cat /var/lib/misc/dnsmasq-vlan100.leases /var/lib/misc/dnsmasq-vlan200.leases"

    CT100=$(ct_ip ct100); CT200=$(ct_ip ct200)
    VM100=$(vm_ip "20:20:68:30:01:00"); VM200=$(vm_ip "20:20:68:30:02:00")
    echo -e "\nIPs por DHCP -> ct100=$CT100  ct200=$CT200  vm100=$VM100  vm200=$VM200"

    echo -e "\n--- Sin NAT en Server 3 ---"
    local res="fail"
    cmd "$S3" "sudo iptables -t nat -S POSTROUTING | grep MASQUERADE" && res="ok"
    if [ "$res" == "fail" ]; then echo "[PASS] Server 3 sin reglas MASQUERADE: fail"; PASS=$((PASS+1))
    else echo "[FAIL] Server 3 tiene MASQUERADE, se esperaba ninguna"; FAILS=$((FAILS+1)); fi

    echo -e "\n--- VLAN 100 ---"
    test_ping ct100 192.168.0.1 ok   "gateway VLAN 100"
    test_ping ct100 "$VM100"    ok   "VM misma VLAN en Server 2 (pasa por OFS)"
    test_ping ct100 8.8.8.8     fail "SIN salida a Internet"
    test_ping ct100 "$CT200"    fail "aislamiento: contenedor VLAN 200"
    test_ping ct100 "$VM200"    fail "aislamiento: VM VLAN 200"

    echo -e "\n--- VLAN 200 ---"
    test_ping ct200 192.168.2.1 ok   "gateway VLAN 200"
    test_ping ct200 "$VM200"    ok   "VM misma VLAN en Server 2 (pasa por OFS)"
    test_ping ct200 8.8.8.8     fail "SIN salida a Internet"
    test_ping ct200 "$CT100"    fail "aislamiento: contenedor VLAN 100"
    test_ping ct200 "$VM100"    fail "aislamiento: VM VLAN 100"

    echo -e "\n========== RESUMEN: $PASS PASS / $FAILS FAIL =========="
    echo "Log guardado en: $LOG"
}

case "${1:-all}" in
    deploy) precheck; deploy ;;
    verify) precheck; verify ;;
    clean)  precheck; clean ;;
    all)    precheck; deploy; verify ;;
    *) echo "Uso: $0 [all|deploy|verify|clean]"; exit 1 ;;
esac
