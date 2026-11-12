from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.database import Base, engine
from app.models import Product, Inventory
from app.routers.products import router as products_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="NEXO",
    description=(
        "Sistema de gestión de pedidos e inventario con monitoreo en tiempo real."
    ),
    version="0.2.0",
    lifespan=lifespan,
)

app.include_router(products_router)


@app.get("/health", tags=["Health"])
def health_check():
    return {
        "status": "healthy",
        "application": "NEXO",
        "version": "0.2.0",
    }


@app.get("/", tags=["General"])
def root():
    return {
        "message": "Conecta tu negocio.",
        "application": "NEXO",
    }
