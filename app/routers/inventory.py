from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Inventory
from app.schemas.inventory import (
    InventoryAdjustment,
    InventoryDetail,
)

router = APIRouter(prefix="/inventory", tags=["Inventory"])

DBSession = Annotated[Session, Depends(get_db)]

def inventory_response(inventory: Inventory):
    return InventoryDetail(
        product_id=inventory.product_id,
        quantity=inventory.quantity,
        minimum_stock=inventory.minimum_stock,
        low_stock=inventory.quantity <= inventory.minimum_stock,
    )

@router.get("/{product_id}", response_model=InventoryDetail)
def get_inventory(product_id: int, db: DBSession):
    inventory = db.scalar(
        select(Inventory).where(Inventory.product_id == product_id)
    )

    if inventory is None:
        raise HTTPException(
            status_code=404,
            detail="Inventario no encontrado",
        )

    return inventory_response(inventory)

@router.post(
    "/{product_id}/adjust",
    response_model=InventoryDetail,
)
def adjust_inventory(
    product_id: int,
    data: InventoryAdjustment,
    db: DBSession,
):
    try:
        inventory = db.scalar(
            select(Inventory)
            .where(Inventory.product_id == product_id)
            .with_for_update()
        )

        if inventory is None:
            raise HTTPException(
                status_code=404,
                detail="Inventario no encontrado",
            )

        new_quantity = inventory.quantity + data.adjustment

        if new_quantity < 0:
            raise HTTPException(
                status_code=409,
                detail="El inventario no puede ser negativo",
            )

        inventory.quantity = new_quantity

        db.commit()
        db.refresh(inventory)

        return inventory_response(inventory)

    except Exception:
        db.rollback()
        raise
