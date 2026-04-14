#!/bin/bash
set -euo pipefail

SWAP_SIZE="${1:-4G}"
SWAP_FILE="/swapfile"

if swapon --show | grep -q "$SWAP_FILE"; then
    echo "Swap ya configurado en $SWAP_FILE"
    swapon --show
    exit 0
fi

if [ -f "$SWAP_FILE" ]; then
    echo "Archivo $SWAP_FILE existe pero no esta activo. Activando..."
else
    echo "Creando swap de $SWAP_SIZE en $SWAP_FILE..."
    fallocate -l "$SWAP_SIZE" "$SWAP_FILE"
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
fi

swapon "$SWAP_FILE"

if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    echo "Agregado a /etc/fstab para persistencia"
fi

sysctl vm.swappiness=10
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

echo "Swap configurado:"
swapon --show
free -h | head -3
