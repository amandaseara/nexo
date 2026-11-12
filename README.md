# NEXO
Sistema de gestión de pedidos e inventario con monitoreo en tiempo real. Desarrollado con Python, FastAPI, PostgreSQL y tecnologías DevOps/DevSecOps.

## Ejecución local

```bash
python3.12 -m venv .venv
source .venv/bin/activate

pip install -r requirements-dev.txt

uvicorn app.main:app --reload
