from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Product, Inventory, Order, OrderItem
from app.schemas.order import OrderCreate, OrderResponse

router = APIRouter(prefix="/orders", tags=["Orders"])

DBSession = Annotated[Session, Depends(get_db)]

@router.post("", response_model=OrderResponse, status_code=201)
def create_order(data: OrderCreate, db: DBSession):

    # No se aceptan productos repetidos en un mismo pedido
    product_ids = [item.product_id for item in data.items]

    if len(product_ids) != len(set(product_ids)):
        raise HTTPException(
            status_code=422,
            detail="No se permiten productos duplicados",
        )

    requested_quantities = {
        item.product_id: item.quantity for item in data.items
    }

    sorted_ids = sorted(product_ids)

    try:
        statement = (
            select(Inventory)
            .where(Inventory.product_id.in_(sorted_ids))
            .order_by(Inventory.product_id)
            .with_for_update()
        )

        inventories = {
            inventory.product_id: inventory
            for inventory in db.scalars(statement).all()
        }

        products = {
            product.id: product
            for product in db.scalars(
                select(Product).where(Product.id.in_(sorted_ids))
            ).all()
        }

        order_items = []
        total = Decimal("0.00")

        for product_id in sorted_ids:
            product = products.get(product_id)
            inventory = inventories.get(product_id)

            if product is None or inventory is None:
                raise HTTPException(
                    status_code=404,
                    detail=f"Producto {product_id} no encontrado",
                )

            if not product.active:
                raise HTTPException(
                    status_code=409,
                    detail=f"Producto {product_id} inactivo",
                )

            quantity = requested_quantities[product_id]

            if inventory.quantity < quantity:
                raise HTTPException(
                    status_code=409,
                    detail=f"Stock insuficiente para {product.name}",
                )

            inventory.quantity -= quantity

            order_items.append(
                OrderItem(
                    product_id=product_id,
                    quantity=quantity,
                    unit_price=product.price,
                )
            )

            total += product.price * quantity

        order = Order(
            status="confirmed",
            total_amount=total,
            items=order_items,
        )

        db.add(order)
        db.commit()
        db.refresh(order)

        return order

    except Exception:
        db.rollback()
        raise

@router.get("", response_model=list[OrderResponse])
def list_orders(db: DBSession):
    statement = select(Order).order_by(Order.id.desc())
    return db.scalars(statement).all()

@router.get("/{order_id}", response_model=OrderResponse)
def get_order(order_id: int, db: DBSession):
    order = db.get(Order, order_id)

    if order is None:
        raise HTTPException(
            status_code=404,
            detail="Pedido no encontrado",
        )

    return order
