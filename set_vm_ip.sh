#!/bin/bash
# set_vm_ip.sh - Asigna IP estática a una VM cirros entrando por su consola serial
# (socket /tmp/<VM>.serial creado por create_vm.sh). Se usa cuando la red NO tiene DHCP.
# Se ejecuta en el worker (Server 2), lanzado desde el Server 4.
# Uso: ./set_vm_ip.sh <NOMBRE_VM> <IP/PREFIJO> <GATEWAY>
# Ejemplo: ./set_vm_ip.sh vm100 192.168.0.20/24 192.168.0.1
#
# Sin DHCP, cirros tarda en arrancar (reintenta DHCP y metadata ~1-2 min),
# por eso se espera hasta 300 s al prompt de login.

VM_NAME="$1"
IP="$2"
GW="$3"
SERIAL="/tmp/${VM_NAME}.serial"

[ -S "$SERIAL" ] || { echo "[ERROR] No existe el socket $SERIAL (¿VM creada con create_vm.sh nuevo?)"; exit 1; }
echo "[INFO] Esperando login de $VM_NAME por consola serial (hasta 300 s)..."

sudo python3 - "$SERIAL" "$IP" "$GW" <<'PY'
import socket, sys, time
path, ip, gw = sys.argv[1:4]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(path)
s.settimeout(1)
buf = b""

def send(line):
    s.sendall(line.encode() + b"\n")

def wait(patterns, timeout, poke=0):
    """Lee la consola hasta ver alguno de los patrones. poke>0: envía Enter cada 'poke' s."""
    global buf
    end, last = time.time() + timeout, 0
    while time.time() < end:
        try:
            data = s.recv(4096)
            if data:
                buf += data
        except socket.timeout:
            pass
        for p in patterns:
            if p.encode() in buf:
                out = buf.decode(errors="ignore"); buf = b""
                return p, out
        if poke and time.time() - last > poke:
            send(""); last = time.time()
    return None, buf.decode(errors="ignore")

# 1. Login (si ya hay sesión abierta, sigue de largo)
found, _ = wait(["login:", "$ "], 300, poke=5)
if found is None:
    print("[ERROR] No apareció el login en la consola serial."); sys.exit(1)
if found == "login:":
    send("cirros")
    wait(["assword:"], 20)
    send("gocubsgo")
    if wait(["$ "], 30)[0] is None:
        print("[ERROR] Login fallido."); sys.exit(1)

# 2. Configurar IP, ruta por defecto y DNS
cmds = [
    "sudo ip addr flush dev eth0",
    f"sudo ip addr add {ip} dev eth0",
    "sudo ip link set eth0 up",
    f"sudo ip route replace default via {gw}",
    "echo nameserver 8.8.8.8 | sudo tee /etc/resolv.conf >/dev/null",
]
for c in cmds:
    send(c); wait(["$ "], 10)

# 3. Evidencia desde dentro de la VM
# marcadores con $((..)): el eco de lo tecleado no coincide con la salida real
send("echo INI_$((40+2)); ip -4 addr show eth0; ip route; ping -c 2 -W 2 8.8.8.8; echo FIN_$((40+2))")
_, out = wait(["FIN_42"], 30)
print(out.split("INI_42", 1)[-1].replace("FIN_42", "").strip())
send("exit")
PY
RC=$?

[ $RC -eq 0 ] && echo "[DONE] $VM_NAME configurada con $IP (gw $GW)." || echo "[ERROR] Falló la configuración de $VM_NAME."
exit $RC
