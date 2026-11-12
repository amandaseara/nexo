from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

class ProductCreate(BaseModel):
    name: str = Field(min_length=1, max_length=150)
    sku: str = Field(min_length=1, max_length=50)
    description: str | None = Field(default=None, max_length=500)
    price: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    quantity: int = Field(default=0, ge=0)
    minimum_stock: int = Field(default=5, ge=0)

class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=500)
    price: Decimal | None = Field(
        default=None, ge=0, max_digits=12, decimal_places=2
    )
    active: bool | None = None

class InventoryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    quantity: int
    minimum_stock: int

class ProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    sku: str
    description: str | None
    price: Decimal
    active: bool
    inventory: InventoryResponse
