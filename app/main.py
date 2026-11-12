
from fastapi import FastAPI, HTTPException
from sqlalchemy import text

from app.database import engine

from app.routers.products import router as products_router
from app.routers.orders import router as orders_router
from app.routers.inventory import router as inventory_router

app = FastAPI(
    title="NEXO",
    description=(
        "Sistema de gestión de pedidos e inventario con monitoreo en tiempo real."
    ),
    version="0.2.0",
)

app.include_router(products_router)
app.include_router(orders_router)
app.include_router(inventory_router)

@app.get("/health", tags=["Health"])
def health_check():
    """Comprueba que el proceso de la API está activo."""
    return {
        "status": "healthy",
        "application": "NEXO",
        "version": "0.2.0",
    }

@app.get("/health/ready", tags=["Health"])
def readiness_check():
    """Comprueba que la API puede conectarse a PostgreSQL."""
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))

        return {
            "status": "ready",
            "application": "NEXO",
            "database": "connected",
        }

    except Exception:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not_ready",
                "application": "NEXO",
                "database": "disconnected",
            },
        )

@app.get("/", tags=["General"])
def root():
    return {
        "message": "Conecta tu negocio.",
        "application": "NEXO",
    }
