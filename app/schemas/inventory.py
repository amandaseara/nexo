from pydantic import BaseModel, Field

class InventoryAdjustment(BaseModel):
    adjustment: int = Field(
        ne=0,
        description="Cantidad positiva o negativa a ajustar",
    )

class InventoryDetail(BaseModel):
    product_id: int
    quantity: int
    minimum_stock: int
    low_stock: bool
