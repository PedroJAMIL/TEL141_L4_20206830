#!/bin/bash
# DEV/actividad_2/script.sh - ACTIVIDAD 2: redes aisladas (VLAN 100 y 200) SIN DHCP y con salida a Internet.
# Script principal. Se ejecuta SOLO en el Server 4 (rol Cliente); todo lo demás va por SSH:
#     ssh user@ip 'bash -s' < ./script.sh "param1" "param2"
#
# Uso: ./DEV/actividad_2/script.sh            -> limpia, despliega y verifica
#      ./DEV/actividad_2/script.sh deploy     -> solo limpia y despliega
#      ./DEV/actividad_2/script.sh verify     -> solo pruebas (evidencias)
#      ./DEV/actividad_2/script.sh clean      -> deja los 3 servers limpios
#
# Diferencia con la Actividad 1: create_network_vlan.sh se llama con "no" (sin dnsmasq ni
# namespaces) y cada equipo recibe IP ESTÁTICA:
#   VLAN 100 (192.168.0.0/24, gw .1): ct100 = .10   vm100 = .20
#   VLAN 200 (192.168.2.0/24, gw .1): ct200 = .10   vm200 = .20

DIR="$(cd "$(dirname "$0")" && pwd)"      # carpeta de la actividad (aquí queda el log)
ROOT="$(cd "$DIR/../.." && pwd)"          # raíz del repo (scripts base)
USR="ubuntu"
S1="10.0.10.1"; S2="10.0.10.2"; S3="10.0.10.3"
DATA_IF="ens4"
BR="br-int"

V1=100; NET1="192.168.0.0/24"; GW1="192.168.0.1"; CT100="192.168.0.10"; VM100="192.168.0.20"
V2=200; NET2="192.168.2.0/24"; GW2="192.168.2.1"; CT200="192.168.2.10"; VM200="192.168.2.20"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
LOG="$DIR/act2_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
PASS=0; FAILS=0

# ---------- helpers ----------
run() {   # run <ip> <script> [args...]  -> ejecuta un script local en el nodo remoto
    local ip="$1" sc="$2"; shift 2
    echo -e "\n>>> [$ip] $sc $*" >&2
    ssh "${SSH_OPTS[@]}" "$USR@$ip" 'bash -s' "$@" < "$ROOT/$sc"
}
cmd() {   # cmd <ip> "<comando>"
    local ip="$1"; shift
    echo -e "\n>>> [$ip] $*" >&2
    ssh -n "${SSH_OPTS[@]}" "$USR@$ip" "$@"
}
ct_exec() {   # ct_exec <contenedor> "<comando>"  (contenedores del Server 1)
    local name="$1"; shift
    echo -e "\n>>> [$S1:$name] $*" >&2
    ssh "${SSH_OPTS[@]}" "$USR@$S1" 'bash -s' "$name" "'$*'" <<'EOF'
if sudo docker inspect "$1" >/dev/null 2>&1; then sudo docker exec "$1" sh -c "$2"
else sudo ip netns exec "$1" sh -c "$2"; fi
EOF
}
result() {   # result <ok|fail obtenido> <esperado> <descripción>
    if [ "$1" == "$2" ]; then echo "[PASS] $3: $1"; PASS=$((PASS+1))
    else echo "[FAIL] $3: $1, se esperaba $2"; FAILS=$((FAILS+1)); fi
}
test_ping() {   # test_ping <contenedor> <destino> <ok|fail> <descripción>
    local res="fail"
    ct_exec "$1" "ping -c 2 -W 2 $2" && res="ok"
    result "$res" "$3" "$1 -> $2 ($4)"
}

# ---------- 0. prechequeo ----------
precheck() {
    for f in init_master.sh init_worker.sh create_network_vlan.sh internet_to_network.sh \
             create_vm.sh create_container.sh set_vm_ip.sh reset_node.sh; do
        [ -f "$ROOT/$f" ] || { echo "[ERROR] Falta $f en $ROOT"; exit 1; }
    done
    grep -q -- '-serial' "$ROOT/create_vm.sh" || { echo "[ERROR] create_vm.sh no tiene la consola serial (usa la versión nueva)"; exit 1; }
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

    echo -e "\n========== 3. REDES VLAN SIN DHCP (Server 3) =========="
    run "$S3" create_network_vlan.sh "$V1" "$NET1" no
    run "$S3" create_network_vlan.sh "$V2" "$NET2" no

    echo -e "\n========== 4. SALIDA A INTERNET (Server 3) =========="
    run "$S3" internet_to_network.sh "$V1" "$NET1"
    run "$S3" internet_to_network.sh "$V2" "$NET2"
    # Redes AISLADAS: no se ejecuta routing_networks.sh

    echo -e "\n========== 5. CÓMPUTO CON IP ESTÁTICA =========="
    run "$S1" create_container.sh ct100 "$BR" "$V1" "$CT100/24" "$GW1"
    run "$S1" create_container.sh ct200 "$BR" "$V2" "$CT200/24" "$GW2"
    run "$S2" create_vm.sh vm100 "$BR" "$V1" 5901
    run "$S2" create_vm.sh vm200 "$BR" "$V2" 5902

    echo -e "\n========== 6. IP ESTÁTICA EN LAS VMs (consola serial) =========="
    run "$S2" set_vm_ip.sh vm100 "$VM100/24" "$GW1"
    run "$S2" set_vm_ip.sh vm200 "$VM200/24" "$GW2"
}

verify() {
    echo -e "\n========== 7. VERIFICACIÓN =========="
    cmd "$S3" "sudo ovs-vsctl show; ip -br addr show | grep gw_vlan"
    cmd "$S3" "sudo iptables -S FORWARD; sudo iptables -t nat -S POSTROUTING; sysctl net.ipv4.ip_forward"
    cmd "$S1" "sudo ovs-vsctl show"
    cmd "$S2" "sudo ovs-vsctl show; pgrep -a qemu-system"

    echo -e "\n--- Sin DHCP ---"
    local res="fail"
    cmd "$S3" "pgrep -a dnsmasq || ip netns list | grep ns-dhcp" && res="ok"
    result "$res" fail "Server 3 sin dnsmasq ni namespaces DHCP"
    res="fail"
    ct_exec ct100 "udhcpc -i eth0 -n -q -t 3 -T 1 -s /bin/true" && res="ok"
    result "$res" fail "ct100 pide DHCP y nadie responde"
    ct_exec ct100 "ip -4 addr show eth0; ip route"
    ct_exec ct200 "ip -4 addr show eth0; ip route"

    echo -e "\n--- VLAN 100 ---"
    test_ping ct100 "$GW1"   ok   "gateway VLAN 100"
    test_ping ct100 "$VM100" ok   "VM misma VLAN en Server 2 (pasa por OFS)"
    test_ping ct100 8.8.8.8  ok   "salida a Internet (NAT)"
    test_ping ct100 "$CT200" fail "aislamiento: contenedor VLAN 200"
    test_ping ct100 "$VM200" fail "aislamiento: VM VLAN 200"

    echo -e "\n--- VLAN 200 ---"
    test_ping ct200 "$GW2"   ok   "gateway VLAN 200"
    test_ping ct200 "$VM200" ok   "VM misma VLAN en Server 2 (pasa por OFS)"
    test_ping ct200 8.8.8.8  ok   "salida a Internet (NAT)"
    test_ping ct200 "$CT100" fail "aislamiento: contenedor VLAN 100"
    test_ping ct200 "$VM100" fail "aislamiento: VM VLAN 100"

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
