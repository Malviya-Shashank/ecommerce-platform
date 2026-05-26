"""
Product Service - E-Commerce Platform
Handles product catalog, inventory, and search.
"""

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List
from decimal import Decimal
import os, logging, asyncpg
from contextlib import asynccontextmanager

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("product-service")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://product_service:password@localhost:5432/product_service")


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=5, max_size=20, command_timeout=60)
    async with app.state.db_pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS products (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                description TEXT,
                price DECIMAL(10,2) NOT NULL,
                sku VARCHAR(100) UNIQUE NOT NULL,
                category VARCHAR(100),
                stock_quantity INTEGER DEFAULT 0,
                is_active BOOLEAN DEFAULT TRUE,
                image_url TEXT,
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)
    logger.info("Product Service started successfully")
    yield
    await app.state.db_pool.close()


app = FastAPI(title="Product Service", version="1.0.0", root_path="/api/v1/products", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])


class ProductCreate(BaseModel):
    name: str
    description: Optional[str] = None
    price: Decimal
    sku: str
    category: Optional[str] = None
    stock_quantity: int = 0
    image_url: Optional[str] = None


class ProductResponse(BaseModel):
    id: int
    name: str
    description: Optional[str]
    price: Decimal
    sku: str
    category: Optional[str]
    stock_quantity: int
    is_active: bool
    created_at: datetime


@app.get("/healthz", tags=["health"])
async def health_check():
    return {"status": "healthy", "service": "product-service", "version": "1.0.0"}


@app.get("/readyz", tags=["health"])
async def readiness_check():
    try:
        async with app.state.db_pool.acquire() as conn:
            await conn.execute("SELECT 1")
        return {"status": "ready"}
    except Exception:
        raise HTTPException(status_code=503, detail="Service not ready")


@app.post("/", response_model=ProductResponse, status_code=status.HTTP_201_CREATED, tags=["products"])
async def create_product(product: ProductCreate):
    try:
        async with app.state.db_pool.acquire() as conn:
            row = await conn.fetchrow(
                """INSERT INTO products (name, description, price, sku, category, stock_quantity, image_url)
                   VALUES ($1, $2, $3, $4, $5, $6, $7)
                   RETURNING id, name, description, price, sku, category, stock_quantity, is_active, created_at""",
                product.name, product.description, product.price, product.sku,
                product.category, product.stock_quantity, product.image_url,
            )
            return ProductResponse(**dict(row))
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=409, detail="Product with this SKU already exists")


@app.get("/{product_id}", response_model=ProductResponse, tags=["products"])
async def get_product(product_id: int):
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM products WHERE id = $1 AND is_active = TRUE", product_id)
        if not row:
            raise HTTPException(status_code=404, detail="Product not found")
        return ProductResponse(**dict(row))


@app.get("/", tags=["products"])
async def list_products(category: Optional[str] = None, skip: int = 0, limit: int = 20):
    async with app.state.db_pool.acquire() as conn:
        if category:
            rows = await conn.fetch(
                "SELECT * FROM products WHERE category = $1 AND is_active = TRUE ORDER BY id LIMIT $2 OFFSET $3",
                category, limit, skip,
            )
        else:
            rows = await conn.fetch(
                "SELECT * FROM products WHERE is_active = TRUE ORDER BY id LIMIT $1 OFFSET $2", limit, skip,
            )
        return [ProductResponse(**dict(row)) for row in rows]


@app.put("/{product_id}/stock", tags=["products"])
async def update_stock(product_id: int, quantity: int):
    """Update product stock (used by order service)."""
    async with app.state.db_pool.acquire() as conn:
        result = await conn.execute(
            "UPDATE products SET stock_quantity = stock_quantity + $2, updated_at = NOW() WHERE id = $1 AND is_active = TRUE",
            product_id, quantity,
        )
        if result == "UPDATE 0":
            raise HTTPException(status_code=404, detail="Product not found")
        return {"message": "Stock updated"}
