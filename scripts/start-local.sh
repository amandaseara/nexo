#!/usr/bin/env bash
set -euo pipefail

echo "================================"
echo "  NEXO - Desarrollo local"
echo "================================"

echo "[1/4] Iniciando PostgreSQL..."
docker compose up -d postgres

echo "[2/4] Esperando a PostgreSQL..."
until docker compose exec -T postgres \
    pg_isready -U nexo -d nexo >/dev/null 2>&1; do
    sleep 2
done

echo "[3/4] Ejecutando migraciones..."
alembic upgrade head

echo "[4/4] Construyendo e iniciando API..."
docker compose up -d --build api

echo ""
echo "NEXO iniciado."
echo "API: http://localhost:8000"
echo "Swagger: http://localhost:8000/docs"
