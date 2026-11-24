#!/usr/bin/env bash
# Genera tráfico contra la API para poblar los dashboards de Grafana.
# Crea productos, hace pedidos (algunos fallan a propósito por stock
# insuficiente o producto inexistente), repone stock y consulta datos.
#
# Uso: scripts/generate-traffic.sh [BASE_URL] [DURACION_SEGUNDOS]
#   BASE_URL por defecto http://localhost:8000
#   (kubectl port-forward svc/nexo-api 8000:8000 -n nexo)
set -euo pipefail

BASE_URL="${1:-${BASE_URL:-http://localhost:8000}}"
DURATION="${2:-${DURATION:-300}}"
PRODUCTS="${PRODUCTS:-5}"
RUN_ID="$(date +%s)"

api() {
    # Imprime solo el código HTTP; el cuerpo no interesa.
    curl -s -o /dev/null -w '%{http_code}' "$@" || echo "000"
}

curl -sf "$BASE_URL/health" >/dev/null \
    || { echo "La API no responde en $BASE_URL" >&2; exit 1; }

echo "Creando $PRODUCTS productos de prueba..."
PRODUCT_IDS=()
for i in $(seq 1 "$PRODUCTS"); do
    id=$(curl -s -X POST "$BASE_URL/products" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"Producto carga $i\",\"sku\":\"LOAD-$RUN_ID-$i\",\"price\":\"$((RANDOM % 90 + 10)).50\",\"quantity\":50,\"minimum_stock\":5}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
    PRODUCT_IDS+=("$id")
done
echo "Productos: ${PRODUCT_IDS[*]}"

echo "Generando tráfico durante ${DURATION}s contra $BASE_URL (Ctrl+C para parar)..."
END=$((SECONDS + DURATION))
ok=0; rejected=0; total=0
while (( SECONDS < END )); do
    pid=${PRODUCT_IDS[$((RANDOM % ${#PRODUCT_IDS[@]}))]}
    roll=$((RANDOM % 100))

    if (( roll < 45 )); then
        # Pedido normal (puede fallar por stock si se agota)
        code=$(api -X POST "$BASE_URL/orders" -H 'Content-Type: application/json' \
            -d "{\"items\":[{\"product_id\":$pid,\"quantity\":$((RANDOM % 3 + 1))}]}")
        [[ $code == 201 ]] && ok=$((ok + 1)) || rejected=$((rejected + 1))
    elif (( roll < 50 )); then
        # Pedido que supera el stock -> 409
        api -X POST "$BASE_URL/orders" -H 'Content-Type: application/json' \
            -d "{\"items\":[{\"product_id\":$pid,\"quantity\":100000}]}" >/dev/null
        rejected=$((rejected + 1))
    elif (( roll < 53 )); then
        # Producto inexistente -> 404
        api -X POST "$BASE_URL/orders" -H 'Content-Type: application/json' \
            -d '{"items":[{"product_id":99999999,"quantity":1}]}' >/dev/null
        rejected=$((rejected + 1))
    elif (( roll < 60 )); then
        # Reposición de stock
        api -X POST "$BASE_URL/inventory/$pid/adjust" -H 'Content-Type: application/json' \
            -d "{\"adjustment\":$((RANDOM % 20 + 10))}" >/dev/null
    elif (( roll < 75 )); then
        api "$BASE_URL/products" >/dev/null
    elif (( roll < 85 )); then
        api "$BASE_URL/inventory/$pid" >/dev/null
    elif (( roll < 95 )); then
        api "$BASE_URL/orders" >/dev/null
    else
        api "$BASE_URL/orders/99999999" >/dev/null
    fi

    total=$((total + 1))
    if (( total % 100 == 0 )); then
        echo "  $total peticiones | pedidos ok: $ok | rechazados: $rejected"
    fi
    sleep "0.0$((RANDOM % 9 + 1))"
done

echo "Fin: $total peticiones, $ok pedidos confirmados, $rejected rechazados."
