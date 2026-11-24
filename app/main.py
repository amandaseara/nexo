from fastapi import FastAPI, HTTPException
from sqlalchemy import text

from app.config import settings
from app.database import engine

from app.routers.products import router as products_router
from app.routers.orders import router as orders_router
from app.routers.inventory import router as inventory_router

app = FastAPI(
    title=settings.app_name,
    description=(
        "Sistema de gestión de pedidos e inventario con monitoreo en tiempo real."
    ),
    version=settings.app_version,
)

app.include_router(products_router)
app.include_router(orders_router)
app.include_router(inventory_router)


@app.get("/health", tags=["Health"])
def health_check():
    """Comprueba que el proceso de la API está activo."""
    return {
        "status": "healthy",
        "application": settings.app_name,
        "version": settings.app_version,
    }


@app.get("/health/ready", tags=["Health"])
def readiness_check():
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))

        return {
            "status": "ready",
            "application": settings.app_name,
            "database": "connected",
        }

    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not_ready",
                "application": settings.app_name,
                "database": "disconnected",
            },
        ) from exc


@app.get("/", tags=["General"])
def root():
    return {
        "message": "Conecta tu negocio.",
        "application": settings.app_name,
    }
