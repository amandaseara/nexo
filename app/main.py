from fastapi import FastAPI

app = FastAPI(
    title="NEXO",
    description=(
        "Sistema de gestión de pedidos e inventario con monitoreo en tiempo real."
    ),
    version="0.1.0"
)


@app.get("/health", tags=["Health"])
def health_check():
    return {
        "status": "healthy",
        "application": "NEXO",
        "version": "0.1.0"
    }


@app.get("/", tags=["General"])
def root():
    return {
        "message": "Conecta tu negocio.",
        "application": "NEXO"
    }
