#!/bin/bash
# setup_ssh.sh - Se ejecuta UNA sola vez en el Server 4 (rol Cliente).
# Genera una llave ECDSA de 256 bits, la copia a los nodos del slice y
# verifica/configura sudo sin contraseña (lo pide la rúbrica).
# Uso: ./setup_ssh.sh        (pedirá la contraseña "ubuntu" por cada nodo, solo esta vez)

USR="ubuntu"
NODES="10.0.10.1 10.0.10.2 10.0.10.3 10.0.10.5"   # server1, server2, server3, ofs
KEY="$HOME/.ssh/id_ecdsa"

# 1. Par de llaves ECDSA 256 sin passphrase
if [ ! -f "$KEY" ]; then
    ssh-keygen -t ecdsa -b 256 -N "" -f "$KEY"
    echo "[OK] Llave $KEY creada."
else
    echo "[INFO] Llave $KEY ya existe."
fi

for ip in $NODES; do
    echo -e "\n=== $ip ==="
    # 2. Copiar llave pública (última vez que pide contraseña)
    ssh-copy-id -i "${KEY}.pub" -o StrictHostKeyChecking=accept-new "$USR@$ip"

    # 3. Probar SSH sin contraseña
    if ! ssh -o BatchMode=yes "$USR@$ip" true; then
        echo "[ERROR] $ip sigue pidiendo contraseña."; continue
    fi
    echo "[OK] SSH passwordless a $ip."

    # 4. sudo sin contraseña (en muchas imágenes cloud ya viene configurado)
    if ssh -o BatchMode=yes "$USR@$ip" 'sudo -n true' 2>/dev/null; then
        echo "[OK] sudo NOPASSWD ya activo en $ip."
    else
        ssh -t "$USR@$ip" "echo '$USR ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-$USR-nopasswd >/dev/null && sudo chmod 440 /etc/sudoers.d/90-$USR-nopasswd"
        ssh -o BatchMode=yes "$USR@$ip" 'sudo -n true' && echo "[OK] sudo NOPASSWD configurado en $ip."
    fi
done

echo -e "\n[DONE] setup_ssh.sh completado."
