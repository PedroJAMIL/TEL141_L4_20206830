#!/bin/bash
# DEV/actividad_4/script.sh - ACTIVIDAD 4: enrutamiento entre redes aisladas (VLAN 100 <-> VLAN 200).
# Script principal. Se ejecuta SOLO en el Server 4 (rol Cliente); todo lo demás va por SSH:
#     ssh user@ip 'bash -s' < ./script.sh "param1" "param2"
#
# Uso: ./DEV/actividad_4/script.sh            -> limpia, despliega y verifica
#      ./DEV/actividad_4/script.sh deploy     -> solo limpia y despliega
#      ./DEV/actividad_4/script.sh verify     -> solo pruebas (evidencias)
#      ./DEV/actividad_4/script.sh clean      -> deja los 3 servers limpios
#
# Topología (según la figura):
#   VLAN 100 (192.168.0.0/24, gw .1): SIN DHCP -> IP estática: ct100 = .10, vm100 = .20
#   VLAN 200 (192.168.2.0/24, gw .1): CON DHCP (dnsmasq vlan 200) -> ct200 y vm200 por DHCP
#   Server 3: routing_networks.sh 100 200 (IPTABLES 1: ruteo entre VLANs). Sin salida a Internet.

DIR="$(cd "$(dirname "$0")" && pwd)"      # carpeta de la actividad (aquí queda el log)
ROOT="$(cd "$DIR/../.." && pwd)"          # raíz del repo (scripts base)
USR="ubuntu"
S1="10.0.10.1"; S2="10.0.10.2"; S3="10.0.10.3"
DATA_IF="ens4"
BR="br-int"

V1=100; NET1="192.168.0.0/24"; GW1="192.168.0.1"; CT100="192.168.0.10"; VM100="192.168.0.20"
V2=200; NET2="192.168.2.0/24"; GW2="192.168.2.1"; RANGE2="192.168.2.10,192.168.2.50"
VM200_MAC="20:20:68:30:02:00"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
LOG="$DIR/act4_$(date +%Y%m%d_%H%M%S).log"
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
    if [ -z "$2" ]; then result "sin-IP" "$3" "$1 -> ? ($4)"; return; fi
    ct_exec "$1" "ping -c 2 -W 2 $2" && res="ok"
    result "$res" "$3" "$1 -> $2 ($4)"
}
ct_ip() { ct_exec "$1" "ip -4 -o addr show eth0" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tail -1; }
vm_ip() { cmd "$S3" "sudo cat /var/lib/misc/dnsmasq-vlan200.leases 2>/dev/null" 2>/dev/null | grep -i "$1" | awk '{print $3}' | tail -1; }

# ---------- 0. prechequeo ----------
precheck() {
    for f in init_master.sh init_worker.sh create_network_vlan.sh routing_networks.sh \
             no_routing_networks.sh create_vm.sh create_container.sh set_vm_ip.sh reset_node.sh; do
        [ -f "$ROOT/$f" ] || { echo "[ERROR] Falta $f en $ROOT"; exit 1; }
    done
    grep -q -- '-serial' "$ROOT/create_vm.sh" || { echo "[ERROR] create_vm.sh no tiene la consola serial"; exit 1; }
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

    echo -e "\n========== 3. REDES (Server 3) =========="
    run "$S3" create_network_vlan.sh "$V1" "$NET1" no                 # VLAN 100 sin DHCP
    run "$S3" create_network_vlan.sh "$V2" "$NET2" yes "$RANGE2"      # VLAN 200 con DHCP

    echo -e "\n========== 4. RUTEO ENTRE VLANs (Server 3, IPTABLES 1) =========="
    run "$S3" routing_networks.sh "$V1" "$V2"
    # Sin salida a Internet: no se ejecuta internet_to_network.sh

    echo -e "\n========== 5. CÓMPUTO =========="
    run "$S1" create_container.sh ct100 "$BR" "$V1" "$CT100/24" "$GW1"   # estática
    run "$S1" create_container.sh ct200 "$BR" "$V2"                      # DHCP
    run "$S2" create_vm.sh vm100 "$BR" "$V1" 5901
    run "$S2" create_vm.sh vm200 "$BR" "$V2" 5902

    echo -e "\n========== 6. IP ESTÁTICA EN vm100 (consola serial) =========="
    run "$S2" set_vm_ip.sh vm100 "$VM100/24" "$GW1" \
        || { echo "[INFO] Reintentando vm100..."; run "$S2" set_vm_ip.sh vm100 "$VM100/24" "$GW1"; }
}

verify() {
    echo -e "\n========== 7. VERIFICACIÓN =========="
    cmd "$S3" "sudo ovs-vsctl show; ip -br addr show | grep gw_vlan; ip netns list; pgrep -a dnsmasq"
    cmd "$S3" "sudo iptables -S FORWARD; sudo iptables -t nat -S POSTROUTING; sysctl net.ipv4.ip_forward"
    cmd "$S1" "sudo ovs-vsctl show"
    cmd "$S2" "sudo ovs-vsctl show; pgrep -a qemu-system"

    echo -e "\n--- DHCP solo en VLAN 200 ---"
    local res="fail"
    cmd "$S3" "pgrep -af '[d]nsmasq.*dhcp_v100'" && res="ok"
    result "$res" fail "Server 3 sin dnsmasq en VLAN 100"
    res="fail"
    cmd "$S3" "pgrep -af '[d]nsmasq.*dhcp_v200'" && res="ok"
    result "$res" ok "Server 3 con dnsmasq en VLAN 200"

    echo -e "\nEsperando 30 s a que vm200 obtenga IP por DHCP..."
    sleep 30
    cmd "$S3" "sudo cat /var/lib/misc/dnsmasq-vlan200.leases"
    CT200=$(ct_ip ct200); VM200=$(vm_ip "$VM200_MAC")
    echo -e "\nIPs -> ct100=$CT100 (estática)  vm100=$VM100 (estática)  ct200=$CT200 (DHCP)  vm200=$VM200 (DHCP)"

    echo -e "\n--- Dentro de cada VLAN ---"
    test_ping ct100 "$GW1"   ok "gateway VLAN 100"
    test_ping ct100 "$VM100" ok "VM misma VLAN 100 en Server 2"
    test_ping ct200 "$GW2"   ok "gateway VLAN 200"
    test_ping ct200 "$VM200" ok "VM misma VLAN 200 en Server 2"

    echo -e "\n--- Ruteo entre VLANs (pasa por Server 3) ---"
    test_ping ct100 "$CT200" ok "VLAN 100 -> contenedor VLAN 200"
    test_ping ct100 "$VM200" ok "VLAN 100 -> VM VLAN 200"
    test_ping ct200 "$CT100" ok "VLAN 200 -> contenedor VLAN 100"
    test_ping ct200 "$VM100" ok "VLAN 200 -> VM VLAN 100"
    ct_exec ct100 "traceroute -n -m 3 -w 2 $CT200" || true    # el salto 1 debe ser 192.168.0.1

    echo -e "\n--- Sin salida a Internet ---"
    test_ping ct100 8.8.8.8 fail "SIN Internet desde VLAN 100"
    test_ping ct200 8.8.8.8 fail "SIN Internet desde VLAN 200"

    echo -e "\n--- Ciclo de vida: quitar y volver a poner el ruteo ---"
    run "$S3" no_routing_networks.sh "$V1" "$V2"
    test_ping ct100 "$CT200" fail "sin ruteo: VLAN 100 -> VLAN 200 bloqueado"
    run "$S3" routing_networks.sh "$V1" "$V2"
    test_ping ct100 "$CT200" ok "ruteo restaurado: VLAN 100 -> VLAN 200"

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
