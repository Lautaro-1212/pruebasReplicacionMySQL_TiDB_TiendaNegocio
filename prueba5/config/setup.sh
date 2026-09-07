#!/bin/bash

set -e

SERVICE_FILE="./tikv.service"

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
echo "       CONFIGURACIÓN DEL CLÚSTER"
echo "========================================"
echo

# ============================================================
# PD
# ============================================================

info "Configuración de PD"
echo

read -rp "  IP/host de PD: " PD_HOST

if [[ -z "$PD_HOST" ]]; then
    error "Debés indicar la IP o hostname de PD."
    exit 1
fi

read -rp "  Puerto de PD [2379]: " PD_PORT
PD_PORT=${PD_PORT:-2379}

PD_ADDRESS="${PD_HOST}:${PD_PORT}"

echo
ok "PD configurado: $PD_ADDRESS"

# ============================================================
# CANTIDAD DE TiKV
# ============================================================

echo
info "Configuración de nodos TiKV"
echo

read -rp "  ¿Cuántos nodos TiKV querés configurar? [1]: " TIKV_COUNT
TIKV_COUNT=${TIKV_COUNT:-1}

if ! [[ "$TIKV_COUNT" =~ ^[0-9]+$ ]] || [[ "$TIKV_COUNT" -lt 1 ]]; then
    error "La cantidad de nodos debe ser un número mayor a 0."
    exit 1
fi

# Arrays
declare -a NODE_HOSTS
declare -a NODE_USERS
declare -a NODE_SSH_PORTS
declare -a NODE_IPS

# ============================================================
# DATOS DE CADA TiKV
# ============================================================

for ((i=1; i<=TIKV_COUNT; i++)); do

    echo
    echo "----------------------------------------"
    echo "  NODO TiKV #$i"
    echo "----------------------------------------"

    read -rp "  IP/host: " NODE_HOST

    if [[ -z "$NODE_HOST" ]]; then
        error "La IP/host no puede estar vacía."
        exit 1
    fi

    read -rp "  Usuario SSH [ubuntu]: " NODE_USER
    NODE_USER=${NODE_USER:-ubuntu}

    read -rp "  Puerto SSH [22]: " NODE_SSH_PORT
    NODE_SSH_PORT=${NODE_SSH_PORT:-22}

    NODE_HOSTS+=("$NODE_HOST")
    NODE_USERS+=("$NODE_USER")
    NODE_SSH_PORTS+=("$NODE_SSH_PORT")

done

# ============================================================
# MOSTRAR CONFIGURACIÓN
# ============================================================

echo
echo "========================================"
echo "       RESUMEN DE CONFIGURACIÓN"
echo "========================================"
echo

echo "  PD:"
echo "    $PD_ADDRESS"
echo

echo "  TiKV:"

for ((i=0; i<TIKV_COUNT; i++)); do
    echo "    #$((i+1)) ${NODE_USERS[$i]}@${NODE_HOSTS[$i]}:${NODE_SSH_PORTS[$i]}"
done

echo

read -rp "¿Continuar? [S/n]: " CONFIRM
CONFIRM=${CONFIRM:-S}

if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo
    info "Configuración cancelada."
    exit 0
fi

# ============================================================
# COMPROBAR PD
# ============================================================

echo
info "Comprobando conexión con PD..."

if ! curl -sf "http://${PD_HOST}:${PD_PORT}/pd/api/v1/stores" >/dev/null; then
    error "No se pudo conectar con PD en $PD_ADDRESS."
    echo
    echo "Verificá que:"
    echo "  - PD esté ejecutándose."
    echo "  - El puerto $PD_PORT esté accesible."
    echo "  - La IP/hostname sea correcta."
    exit 1
fi

ok "PD accesible"

# ============================================================
# CONFIGURAR CADA TiKV
# ============================================================

for ((i=0; i<TIKV_COUNT; i++)); do

    NODE_HOST="${NODE_HOSTS[$i]}"
    NODE_USER="${NODE_USERS[$i]}"
    NODE_SSH_PORT="${NODE_SSH_PORTS[$i]}"

    echo
    echo "========================================"
    echo "       TiKV #$((i+1))"
    echo "========================================"
    echo

    info "Comprobando SSH..."

    if ! ssh \
        -p "$NODE_SSH_PORT" \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "${NODE_USER}@${NODE_HOST}" \
        "echo connected" >/dev/null 2>&1; then

        error "No se pudo conectar por SSH a ${NODE_USER}@${NODE_HOST}:${NODE_SSH_PORT}"

        echo
        echo "Asegurate de que:"
        echo "  - SSH esté habilitado."
        echo "  - Tu clave SSH esté configurada."
        echo "  - El usuario sea correcto."
        echo "  - El nodo sea accesible."
        exit 1
    fi

    ok "SSH conectado"

    # --------------------------------------------------------
    # Obtener IP que el nodo utiliza para llegar a PD
    # --------------------------------------------------------

    info "Detectando IP del nodo..."

    NODE_IP=$(
        ssh \
            -p "$NODE_SSH_PORT" \
            "${NODE_USER}@${NODE_HOST}" \
            "ip -4 route get ${PD_HOST} | awk '{for(i=1;i<=NF;i++) if(\$i==\"src\") {print \$(i+1); exit}}'"
    )

    if [[ -z "$NODE_IP" ]]; then
        error "No se pudo determinar la IP de $NODE_HOST."
        exit 1
    fi

    NODE_IPS+=("$NODE_IP")

    ok "IP del nodo: $NODE_IP"

    # --------------------------------------------------------
    # Comprobar TiKV
    # --------------------------------------------------------

    info "Comprobando instalación de TiKV..."

    if ! ssh \
        -p "$NODE_SSH_PORT" \
        "${NODE_USER}@${NODE_HOST}" \
        "test -x /opt/tikv/bin/tikv-server"; then

        error "No se encontró TiKV en /opt/tikv/bin/tikv-server."
        echo
        echo "El nodo debe tener TiKV instalado antes de ejecutar este script."
        exit 1
    fi

    ok "TiKV encontrado"

    # --------------------------------------------------------
    # Generar systemd service
    # --------------------------------------------------------

    info "Generando servicio systemd..."

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=TiKV Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=tikv
Group=tikv

ExecStart=/opt/tikv/bin/tikv-server \\
  --pd=${PD_ADDRESS} \\
  --addr=0.0.0.0:20160 \\
  --advertise-addr=${NODE_IP}:20160 \\
  --status-addr=0.0.0.0:20180 \\
  --advertise-status-addr=${NODE_IP}:20180 \\
  --data-dir=/var/lib/tikv

Restart=on-failure
RestartSec=5

LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    ok "Servicio generado"

    # --------------------------------------------------------
    # Transferir service
    # --------------------------------------------------------

    info "Copiando servicio al nodo..."

    scp \
        -P "$NODE_SSH_PORT" \
        "$SERVICE_FILE" \
        "${NODE_USER}@${NODE_HOST}:/tmp/tikv.service" \
        >/dev/null

    ok "Servicio transferido"

    # --------------------------------------------------------
    # Instalar y arrancar
    # --------------------------------------------------------

    info "Instalando TiKV..."

    ssh \
        -p "$NODE_SSH_PORT" \
        "${NODE_USER}@${NODE_HOST}" \
        "sudo mv /tmp/tikv.service /etc/systemd/system/tikv.service && \
         sudo systemctl daemon-reload && \
         sudo systemctl enable tikv >/dev/null && \
         sudo systemctl restart tikv"

    sleep 2

    if ssh \
        -p "$NODE_SSH_PORT" \
        "${NODE_USER}@${NODE_HOST}" \
        "sudo systemctl is-active --quiet tikv"; then

        ok "TiKV iniciado correctamente"

    else

        error "TiKV no pudo iniciarse."

        echo
        echo "Últimos logs:"
        ssh \
            -p "$NODE_SSH_PORT" \
            "${NODE_USER}@${NODE_HOST}" \
            "sudo journalctl -u tikv -n 30 --no-pager"

        exit 1
    fi

done

# ============================================================
# ESPERAR TiKV EN PD
# ============================================================

echo
echo "========================================"
echo "       REGISTRO EN PD"
echo "========================================"
echo

info "Esperando que los TiKV aparezcan como Up..."

MAX_ATTEMPTS=15
ATTEMPT=1

while [[ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]]; do

    STORES_JSON=$(curl -sf \
        "http://${PD_HOST}:${PD_PORT}/pd/api/v1/stores" \
        || true)

    if [[ -z "$STORES_JSON" ]]; then
        echo "    No se pudo consultar PD. Reintentando..."
        sleep 2
        ((ATTEMPT++))
        continue
    fi

    ALL_UP=1

    for ((i=0; i<TIKV_COUNT; i++)); do

        NODE_IP="${NODE_IPS[$i]}"
        NODE_HOST="${NODE_HOSTS[$i]}"

        STATE=$(
            echo "$STORES_JSON" |
            jq -r --arg address "${NODE_IP}:20160" '
                .stores[]
                | select(.store.address == $address)
                | .store.state_name
            ' |
            head -n 1
        )

        if [[ "$STATE" == "Up" ]]; then

            echo "    ✓ $NODE_HOST ($NODE_IP:20160) → Up"

        else

            echo "    → $NODE_HOST ($NODE_IP:20160) → ${STATE:-NO REGISTRADO}"

            ALL_UP=0

        fi

    done

    if [[ "$ALL_UP" -eq 1 ]]; then
        break
    fi

    echo
    echo "    Esperando... ($ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2

    ((ATTEMPT++))

done

# ============================================================
# RESULTADO FINAL
# ============================================================

echo
echo "========================================"
echo "          ESTADO DEL CLÚSTER"
echo "========================================"
echo

STORES_JSON=$(curl -sf \
    "http://${PD_HOST}:${PD_PORT}/pd/api/v1/stores")

if [[ -z "$STORES_JSON" ]]; then
    error "No se pudo obtener el estado final de PD."
    exit 1
fi

echo "  TiKV registrados en PD:"
echo

echo "$STORES_JSON" |
    jq -r '.stores[] |
        "    \(.store.address) → \(.store.state_name)"'

FAILED=0

for ((i=0; i<TIKV_COUNT; i++)); do

    NODE_IP="${NODE_IPS[$i]}"
    NODE_HOST="${NODE_HOSTS[$i]}"

    STATE=$(
        echo "$STORES_JSON" |
        jq -r --arg address "${NODE_IP}:20160" '
            .stores[]
            | select(.store.address == $address)
            | .store.state_name
        ' |
        head -n 1
    )

    if [[ "$STATE" != "Up" ]]; then
        FAILED=1
    fi

done

echo

if [[ "$FAILED" -eq 0 ]]; then

    echo "========================================"
    echo "       CLÚSTER CONFIGURADO"
    echo "========================================"
    echo

    echo "  PD"
    echo "    $PD_ADDRESS"
    echo

    echo "  TiKV"

    for ((i=0; i<TIKV_COUNT; i++)); do
        echo "    ${NODE_IPS[$i]}:20160"
        echo "      SSH: ${NODE_USERS[$i]}@${NODE_HOSTS[$i]}:${NODE_SSH_PORTS[$i]}"
    done

    echo
    echo "  Total TiKV: $TIKV_COUNT"
    echo
    echo "========================================"

else

    error "Uno o más TiKV no están Up en PD."

    echo
    echo "Podés revisar los stores con:"
    echo
    echo "  curl -s http://${PD_HOST}:${PD_PORT}/pd/api/v1/stores | jq"

    exit 1

fi