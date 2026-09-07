#!/bin/bash

VM_PREFIX="tidb-vm"

ok() {
    echo "  ✓ $1"
}

info() {
    echo "  → $1"
}

error() {
    echo "  ✗ $1"
}

clear

echo "========================================"
echo "        CONFIGURACIÓN DEL CLÚSTER"
echo "========================================"
echo

# ==========================================
# Detectar IP de Multipass
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
# Detectar VMs TiKV
# ==========================================

info "Detectando VMs TiKV..."

mapfile -t VM_DATA < <(
    multipass list --format json |
    jq -r --arg prefix "$VM_PREFIX" '
        .list[]
        | select(.name | startswith($prefix))
        | select((.state | ascii_upcase) == "RUNNING")
        | select(.ipv4 | length > 0)
        | "\(.name)|\(.ipv4[0])"
    ' |
    sort
)

if [[ ${#VM_DATA[@]} -eq 0 ]]; then
    error "No se encontraron VMs TiKV ejecutándose."
    echo
    echo "Se esperan VMs con nombres como:"
    echo "  tidb-vm1"
    echo "  tidb-vm2"
    echo "  tidb-vm3"
    exit 1
fi

echo

info "VMs encontradas: ${#VM_DATA[@]}"

declare -a VM_NAMES
declare -a VM_IPS

for DATA in "${VM_DATA[@]}"; do

    VM_NAME="${DATA%%|*}"
    VM_IP="${DATA#*|}"

    VM_NAMES+=("$VM_NAME")
    VM_IPS+=("$VM_IP")

    echo "    $VM_NAME → $VM_IP"

done


# ==========================================
# Generar .env
# ==========================================

echo

info "Generando .env..."

cat > .env <<EOF
PD_HOST=$MULTIPASS_IP
VM_NAME_PREFIX=$VM_PREFIX
TIKV_VM_COUNT=${#VM_NAMES[@]}
EOF

ok ".env generado"


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
# Configurar TiKV en cada VM
# ==========================================

echo

info "Configurando TiKV en las VMs..."

for i in "${!VM_NAMES[@]}"; do

    VM_NAME="${VM_NAMES[$i]}"
    VM_IP="${VM_IPS[$i]}"

    echo
    echo "  --------------------------------------"
    echo "  Configurando: $VM_NAME"
    echo "  IP: $VM_IP"
    echo "  --------------------------------------"

    # --------------------------------------
    # Generar service para esta VM
    # --------------------------------------

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

    # --------------------------------------
    # Transferir service
    # --------------------------------------

    if ! multipass transfer \
        ./tikv.service \
        "$VM_NAME":/tmp/tikv.service >/dev/null; then

        error "No se pudo transferir tikv.service a $VM_NAME."
        exit 1
    fi

    # --------------------------------------
    # Instalar service
    # --------------------------------------

    if ! multipass exec "$VM_NAME" -- sudo mv \
        /tmp/tikv.service \
        /etc/systemd/system/tikv.service; then

        error "No se pudo instalar el servicio TiKV en $VM_NAME."
        exit 1
    fi

    # --------------------------------------
    # Reiniciar TiKV
    # --------------------------------------

    multipass exec "$VM_NAME" -- \
        sudo systemctl daemon-reload

    multipass exec "$VM_NAME" -- \
        sudo systemctl enable tikv >/dev/null

    multipass exec "$VM_NAME" -- \
        sudo systemctl restart tikv

    sleep 2

    # --------------------------------------
    # Verificar TiKV
    # --------------------------------------

    if multipass exec "$VM_NAME" -- \
        sudo systemctl is-active --quiet tikv; then

        ok "$VM_NAME: TiKV iniciado"

    else

        error "$VM_NAME: TiKV no está funcionando."

        echo
        echo "Últimos logs de $VM_NAME:"

        multipass exec "$VM_NAME" -- \
            sudo journalctl -u tikv -n 20 --no-pager

        exit 1
    fi

done


# ==========================================
# Verificar TiKV registrados en PD
# ==========================================

echo

info "Verificando TiKV registrados en PD..."

sleep 10

STORES_JSON=$(
    curl -sf \
        "http://${MULTIPASS_IP}:2379/pd/api/v1/stores"
)

if [[ $? -ne 0 || -z "$STORES_JSON" ]]; then
    error "No se pudo consultar PD."
    exit 1
fi


# ==========================================
# Mostrar stores detectados
# ==========================================

echo

info "TiKV registrados en PD:"

echo "$STORES_JSON" |
    jq -r '
        .stores[] |
        "    \(.store.address) → \(.store.state_name)"
    '


# ==========================================
# Verificar Docker TiKV
# ==========================================

DOCKER_TIKV_OK=$(
    echo "$STORES_JSON" |
    jq -r '
        .stores[]
        | select(.store.address == "'${MULTIPASS_IP}':20160")
        | .store.state_name
    ' |
    head -n 1
)

if [[ "$DOCKER_TIKV_OK" != "Up" ]]; then
    error "El TiKV Docker no aparece como Up en PD."
    exit 1
fi

ok "TiKV Docker registrado en PD"


# ==========================================
# Verificar cada VM
# ==========================================

FAILED=0

for i in "${!VM_NAMES[@]}"; do

    VM_NAME="${VM_NAMES[$i]}"
    VM_IP="${VM_IPS[$i]}"

    STATE=$(
        echo "$STORES_JSON" |
        jq -r --arg address "${VM_IP}:20160" '
            .stores[]
            | select(.store.address == $address)
            | .store.state_name
        ' |
        head -n 1
    )

    if [[ "$STATE" == "Up" ]]; then

        ok "$VM_NAME ($VM_IP:20160) → Up"

    else

        error "$VM_NAME ($VM_IP:20160) → ${STATE:-NO REGISTRADO}"

        FAILED=1

    fi

done


# ==========================================
# Resultado
# ==========================================

if [[ "$FAILED" -ne 0 ]]; then

    echo
    error "Uno o más TiKV no están registrados correctamente en PD."

    echo
    echo "Podés revisar los stores con:"
    echo
    echo "  source .env && curl -s \\"
    echo '    "http://${MULTIPASS_IP}:2379/pd/api/v1/stores" | jq'

    exit 1
fi


# ==========================================
# Resumen
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

for i in "${!VM_NAMES[@]}"; do
    echo "    ${VM_IPS[$i]}:20160        (${VM_NAMES[$i]})"
done

echo

echo "  TiDB"
echo "    localhost:4000"

echo
echo "  Total TiKV:"
echo "    $(( ${#VM_NAMES[@]} + 1 ))"

echo
echo "========================================"
echo "       CONFIGURACIÓN COMPLETADA"
echo "========================================"