from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.product import Inventory, Product
from app.schemas.product import (
    ProductCreate,
    ProductResponse,
    ProductUpdate,
)

router = APIRouter(prefix="/products", tags=["Products"])

DBSession = Annotated[Session, Depends(get_db)]

@router.post("", response_model=ProductResponse, status_code=201)
def create_product(data: ProductCreate, db: DBSession):
    product = Product(
        name=data.name,
        sku=data.sku,
        description=data.description,
        price=data.price,
    )

    product.inventory = Inventory(
        quantity=data.quantity,
        minimum_stock=data.minimum_stock,
    )

    db.add(product)

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="El SKU ya existe o los datos incumplen una restricción",
        )

    db.refresh(product)
    return product

@router.get("", response_model=list[ProductResponse])
def list_products(db: DBSession, skip: int = 0, limit: int = 100):
    if skip < 0 or not 1 <= limit <= 100:
        raise HTTPException(
            status_code=422,
            detail="Parámetros de paginación inválidos",
        )

    statement = select(Product).order_by(Product.id).offset(skip).limit(limit)
    return db.scalars(statement).all()

@router.get("/{product_id}", response_model=ProductResponse)
def get_product(product_id: int, db: DBSession):
    product = db.get(Product, product_id)

    if not product:
        raise HTTPException(
            status_code=404,
            detail="Producto no encontrado",
        )

    return product

@router.put("/{product_id}", response_model=ProductResponse)
def update_product(
    product_id: int,
    data: ProductUpdate,
    db: DBSession,
):
    product = db.get(Product, product_id)

    if not product:
        raise HTTPException(
            status_code=404,
            detail="Producto no encontrado",
        )

    updates = data.model_dump(exclude_unset=True)

    for field, value in updates.items():
        setattr(product, field, value)

    db.commit()
    db.refresh(product)

    return product

@router.delete("/{product_id}", status_code=204)
def delete_product(product_id: int, db: DBSession):
    product = db.get(Product, product_id)

    if not product:
        raise HTTPException(
            status_code=404,
            detail="Producto no encontrado",
        )

    product.active = False
    db.commit()

    return Response(status_code=204)
