#!/bin/bash
# organizar.sh - Reordena el repo al formato pedido en el laboratorio:
#
#   TEL141_L4_20206830/
#   ├── DEV/
#   │   ├── actividad_1/script.sh
#   │   ├── actividad_2/script.sh
#   │   ├── actividad_3/script.sh
#   │   └── actividad_4/script.sh
#   ├── init_master.sh, init_worker.sh, create_network_vlan.sh, ...   (scripts base)
#
# Convierte act1..act4_deploy.sh en DEV/actividad_N/script.sh. Cada script.sh
# usa los scripts base de la raíz del repo y guarda su log en su propia carpeta.
# Uso (en el Server 4, dentro del repo):  ./organizar.sh

cd "$(dirname "$0")" || exit 1

for n in 1 2 3 4; do
    src="act${n}_deploy.sh"
    dir="DEV/actividad_${n}"
    dst="$dir/script.sh"
    if [ ! -f "$src" ]; then echo "[WARN] No existe $src, se omite."; continue; fi
    mkdir -p "$dir"

    python3 - "$src" "$dst" "$n" <<'PY'
import sys
src, dst, n = sys.argv[1:4]
s = open(src).read()
old_dir = 'DIR="$(cd "$(dirname "$0")" && pwd)"'
assert old_dir in s, "no se encontró la línea DIR="
s = s.replace(old_dir,
    'DIR="$(cd "$(dirname "$0")" && pwd)"      # carpeta de la actividad (aquí queda el log)\n'
    'ROOT="$(cd "$DIR/../.." && pwd)"          # raíz del repo (scripts base)')
for a, b in [('"$DIR/$sc"', '"$ROOT/$sc"'),
             ('"$DIR/$f"', '"$ROOT/$f"'),
             ('Falta $f en $DIR', 'Falta $f en $ROOT'),
             ('"$DIR/create_vm.sh"', '"$ROOT/create_vm.sh"'),
             (f'# act{n}_deploy.sh -', f'# DEV/actividad_{n}/script.sh -'),
             (f'./act{n}_deploy.sh', f'./DEV/actividad_{n}/script.sh')]:
    s = s.replace(a, b)
open(dst, 'w').write(s)
PY

    if bash -n "$dst"; then
        chmod +x "$dst"
        mv act"${n}"_*.log "$dir/" 2>/dev/null   # logs anteriores a su carpeta
        rm -f "$src"
        echo "[OK] $src -> $dst"
    else
        echo "[ERROR] $dst quedó con error de sintaxis; se conserva $src."
    fi
done

echo
if command -v tree >/dev/null; then tree -I '*.log' .; else find . -name '*.sh' | sort; fi
