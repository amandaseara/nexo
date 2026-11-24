#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-nexo}"
RELEASE="${RELEASE:-nexo}"
SECRET_NAME="${SECRET_NAME:-nexo-secret}"

kubectl create namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

if kubectl get secret "$SECRET_NAME" \
    -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Database Secret already exists."
    exit 0
fi

PASSWORD=$(openssl rand -hex 24)

DATABASE_URL="postgresql+psycopg://nexo:${PASSWORD}@${RELEASE}-postgres:5432/nexo"

umask 077
SECRET_FILE=$(mktemp)
trap 'rm -f "$SECRET_FILE"' EXIT

printf 'POSTGRES_PASSWORD=%s\nDATABASE_URL=%s\n' \
    "$PASSWORD" "$DATABASE_URL" > "$SECRET_FILE"

kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-env-file="$SECRET_FILE"

unset PASSWORD DATABASE_URL

echo "Database Secret created successfully."
