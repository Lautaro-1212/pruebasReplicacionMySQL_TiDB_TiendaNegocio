#!/bin/bash

VM_NAME="tidb-vm1"

# ==========================================
# Funciones de salida
# ==========================================

ok() {
    echo "  ✓ $1"
}

info() {
    echo "  → $1"
}

error() {
    echo "  ✗ $1"
}

# ==========================================
# Inicio
# ==========================================

clear

echo "========================================"
echo "        CONFIGURACIÓN DEL CLÚSTER"
echo "========================================"
echo

# ==========================================
# Detectar IP del bridge de Multipass
# ==========================================

info "Detectando IP de Multipass..."

MULTIPASS_IP=$(ip -4 addr show mpqemubr0 2>/dev/null | awk '/inet / {
    sub(/\/.*/, "", $2)
    print $2
}')

if [[ -z "$MULTIPASS_IP" ]]; then
    error "No se pudo detectar la IP de mpqemubr0."
    exit 1
fi

ok "Bridge: $MULTIPASS_IP"

# ==========================================
# Detectar IP de la VM
# ==========================================

info "Detectando IP de $VM_NAME..."

VM_IP=$(multipass list | awk -v vm="$VM_NAME" '$1 == vm {
    print $3
}')

if [[ -z "$VM_IP" ]]; then
    error "No se pudo detectar la IP de $VM_NAME."
    exit 1
fi

ok "VM: $VM_IP"

# ==========================================
# Generar .env
# ==========================================

info "Generando .env..."

cat > .env <<EOF
MULTIPASS_IP=$MULTIPASS_IP
TIKV_VM_IP=$VM_IP
VM_NAME=$VM_NAME
EOF

ok ".env generado"

# ==========================================
# Generar servicio TiKV
# ==========================================

info "Generando configuración de TiKV..."

cat > ./tikv.service <<EOF
[Unit]
Description=TiKV Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=tikv
Group=tikv

ExecStart=/opt/tikv/bin/tikv-server \
  --pd=${MULTIPASS_IP}:2379 \
  --addr=0.0.0.0:20160 \
  --advertise-addr=${VM_IP}:20160 \
  --status-addr=0.0.0.0:20180 \
  --advertise-status-addr=${VM_IP}:20180 \
  --data-dir=/var/lib/tikv

Restart=on-failure
RestartSec=5

LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

ok "tikv.service generado"

# ==========================================
# Levantar Docker
# ==========================================

echo
info "Levantando servicios Docker..."

if ! docker compose up -d >/dev/null; then
    error "No se pudieron levantar los servicios Docker."
    exit 1
fi

ok "PD iniciado"
ok "TiKV Docker iniciado"
ok "TiDB iniciado"

# ==========================================
# Configurar TiKV en la VM
# ==========================================

echo
info "Configurando TiKV en $VM_NAME..."

if ! multipass transfer ./tikv.service "$VM_NAME":/tmp/tikv.service >/dev/null; then
    error "No se pudo transferir tikv.service."
    exit 1
fi

if ! multipass exec "$VM_NAME" -- sudo mv \
    /tmp/tikv.service \
    /etc/systemd/system/tikv.service; then
    error "No se pudo instalar el servicio TiKV."
    exit 1
fi

multipass exec "$VM_NAME" -- sudo systemctl daemon-reload
multipass exec "$VM_NAME" -- sudo systemctl enable tikv >/dev/null
multipass exec "$VM_NAME" -- sudo systemctl restart tikv

# ==========================================
# Verificar TiKV
# ==========================================

sleep 3

if multipass exec "$VM_NAME" -- \
    sudo systemctl is-active --quiet tikv; then
    ok "TiKV VM iniciado"
else
    error "TiKV VM no está funcionando."
    echo
    echo "Últimos logs:"
    multipass exec "$VM_NAME" -- \
        sudo journalctl -u tikv -n 20 --no-pager
    exit 1
fi

# ==========================================
# Verificar PD
# ==========================================

echo
info "Verificando TiKV registrados en PD..."

STORE_COUNT=$(curl -s \
    "http://${MULTIPASS_IP}:2379/pd/api/v1/stores" |
    jq -r '.count')

if [[ "$STORE_COUNT" != "2" ]]; then
    error "PD no tiene 2 TiKV registrados. Encontrados: ${STORE_COUNT:-0}"
    exit 1
fi

ok "PD detecta 2 TiKV"

# ==========================================
# Mostrar nodos
# ==========================================

echo
echo "========================================"
echo "           CLÚSTER ACTIVO"
echo "========================================"
echo
echo "  PD"
echo "    $MULTIPASS_IP:2379"
echo
echo "  TiKV"
echo "    $MULTIPASS_IP:20160  (Docker)"
echo "    $VM_IP:20160        (Multipass)"
echo
echo "  TiDB"
echo "    localhost:4000"
echo
echo "========================================"
echo "       CONFIGURACIÓN COMPLETADA"
echo "========================================"