from pydantic import BaseModel, Field, field_validator

class InventoryAdjustment(BaseModel):
    adjustment: int = Field(
        description="Cantidad positiva o negativa a ajustar"
    )

    @field_validator("adjustment")
    @classmethod
    def validate_adjustment(cls, value: int) -> int:
        if value == 0:
            raise ValueError("El ajuste no puede ser cero")
        return value

class InventoryDetail(BaseModel):
    product_id: int
    quantity: int
    minimum_stock: int
    low_stock: bool
