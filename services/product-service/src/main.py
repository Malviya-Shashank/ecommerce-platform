"""
Product Service - E-Commerce Platform
Handles product catalog, inventory, and search.

Exposes:
  - FastAPI REST API on port 8000 (external/client-facing)
  - gRPC server on port 50051 (internal: order-service stock checks)
"""

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List
from decimal import Decimal
import os, logging, asyncpg
from contextlib import asynccontextmanager
from concurrent import futures

import grpc
from grpc_reflection.v1alpha import reflection
from src.generated import product_pb2, product_pb2_grpc

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("product-service")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://product_service:password@localhost:5432/product_service")
GRPC_PORT = int(os.getenv("GRPC_PORT", "50051"))


################################################################################
# gRPC Service Implementation
################################################################################

class ProductGrpcServicer(product_pb2_grpc.ProductServiceServicer):
    """gRPC servicer for internal product queries from order-service."""

    def __init__(self, db_pool):
        self.db_pool = db_pool

    async def GetProduct(self, request, context):
        """Get product details by ID via gRPC."""
        logger.info(f"[gRPC] GetProduct request for product_id={request.product_id}")
        async with self.db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT id, name, description, price, sku, category, stock_quantity, is_active "
                "FROM products WHERE id = $1 AND is_active = TRUE",
                request.product_id,
            )
            if not row:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(f"Product {request.product_id} not found")
                return product_pb2.ProductResponse()

            return product_pb2.ProductResponse(
                id=row["id"],
                name=row["name"],
                description=row["description"] or "",
                price=str(row["price"]),
                sku=row["sku"],
                category=row["category"] or "",
                stock_quantity=row["stock_quantity"],
                is_active=row["is_active"],
            )

    async def CheckStock(self, request, context):
        """Check if sufficient stock is available for a product."""
        logger.info(f"[gRPC] CheckStock for product_id={request.product_id}, qty={request.requested_quantity}")
        async with self.db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT stock_quantity FROM products WHERE id = $1 AND is_active = TRUE",
                request.product_id,
            )
            if not row:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(f"Product {request.product_id} not found")
                return product_pb2.StockCheckResponse(available=False, current_stock=0)

            current_stock = row["stock_quantity"]
            return product_pb2.StockCheckResponse(
                available=current_stock >= request.requested_quantity,
                current_stock=current_stock,
            )

    async def DeductStock(self, request, context):
        """Deduct stock after successful order placement."""
        logger.info(f"[gRPC] DeductStock for product_id={request.product_id}, qty={request.quantity}")
        async with self.db_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT stock_quantity FROM products WHERE id = $1 AND is_active = TRUE",
                request.product_id,
            )
            if not row:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(f"Product {request.product_id} not found")
                return product_pb2.DeductStockResponse(success=False, remaining_stock=0)

            if row["stock_quantity"] < request.quantity:
                context.set_code(grpc.StatusCode.FAILED_PRECONDITION)
                context.set_details(f"Insufficient stock: {row['stock_quantity']} < {request.quantity}")
                return product_pb2.DeductStockResponse(
                    success=False, remaining_stock=row["stock_quantity"]
                )

            result = await conn.fetchrow(
                "UPDATE products SET stock_quantity = stock_quantity - $2, updated_at = NOW() "
                "WHERE id = $1 AND is_active = TRUE RETURNING stock_quantity",
                request.product_id, request.quantity,
            )
            return product_pb2.DeductStockResponse(
                success=True, remaining_stock=result["stock_quantity"]
            )


async def start_grpc_server(db_pool):
    """Start the gRPC server for internal service-to-service communication."""
    server = grpc.aio.server(futures.ThreadPoolExecutor(max_workers=10))
    product_pb2_grpc.add_ProductServiceServicer_to_server(
        ProductGrpcServicer(db_pool), server
    )

    # Enable gRPC reflection for debugging with grpcurl
    SERVICE_NAMES = (
        product_pb2.DESCRIPTOR.services_by_name["ProductService"].full_name,
        reflection.SERVICE_NAME,
    )
    reflection.enable_server_reflection(SERVICE_NAMES, server)

    server.add_insecure_port(f"[::]:{GRPC_PORT}")
    await server.start()
    logger.info(f"gRPC server started on port {GRPC_PORT}")
    return server


################################################################################
# FastAPI Application (external-facing REST API)
################################################################################

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=5, command_timeout=60)
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

    # Start gRPC server alongside FastAPI
    grpc_server = await start_grpc_server(app.state.db_pool)
    logger.info("Product Service started successfully (HTTP + gRPC)")

    yield

    logger.info("Shutting down Product Service...")
    await grpc_server.stop(grace=5)
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
    return {"status": "healthy", "service": "product-service", "version": "1.0.0", "grpc_port": GRPC_PORT}


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
